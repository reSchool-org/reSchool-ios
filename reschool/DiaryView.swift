import SwiftUI
import QuickLook

struct LessonViewModel: Identifiable, Sendable {
    let id: Int
    let num: Int
    let subject: String
    let topic: String
    let teacher: String
    let teacherFull: String
    let homework: String
    let homeworkDeadline: Double?
    let homeworkFiles: [HomeworkFile]
    let mark: String?
    let markDescription: String?
    let markWeight: Double?
    let startTime: String
    let endTime: String

    func with(mark: String?, description: String?) -> LessonViewModel {
        return LessonViewModel(
            id: id,
            num: num,
            subject: subject,
            topic: topic,
            teacher: teacher,
            teacherFull: teacherFull,
            homework: homework,
            homeworkDeadline: homeworkDeadline,
            homeworkFiles: homeworkFiles,
            mark: mark,
            markDescription: description,
            markWeight: markWeight,
            startTime: startTime,
            endTime: endTime
        )
    }
}

struct HomeworkFile: Identifiable, Sendable {
    let id: Int
    let name: String
    let variantId: Int
}

struct ProcessingResult: Sendable {
    let lessons: [String: [LessonViewModel]]
    let newTeachers: [String: (short: String, full: String)]
}

@MainActor
class DiaryViewModel: ObservableObject {
    private let api = APIService.shared

    @Published var currentWeek: [Date] = []
    @Published var selectedDate: Date = Date()
    @Published var lessons: [String: [LessonViewModel]] = [:]
    @Published var isLoading = false
    @Published var error: String?

    @Published var dayOffset: Int = 0

    private var baseDate: Date
    private var teacherCache: [String: (short: String, full: String)] = [:]

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        let now = Date()
        self.baseDate = Calendar.school.startOfDay(for: now)
        generateWeek(for: now)
    }

    func generateWeek(for date: Date) {
        let calendar = Calendar.school
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let startOfWeek = calendar.date(from: components) else { return }

        var week: [Date] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                week.append(day)
            }
        }
        self.currentWeek = week
    }

    func changeWeek(by value: Int) {
        if let newDate = Calendar.school.date(byAdding: .weekOfYear, value: value, to: selectedDate) {
            self.selectedDate = newDate
            generateWeek(for: newDate)

            if let daysDiff = Calendar.school.dateComponents([.day], from: baseDate, to: newDate).day {
                self.dayOffset = daysDiff
            }
            Task { await loadSchedule() }
        }
    }

    func jumpToDate(_ date: Date) {
        self.selectedDate = date
        generateWeek(for: date)

        if let daysDiff = Calendar.school.dateComponents([.day], from: baseDate, to: date).day {
            self.dayOffset = daysDiff
        }
        Task { await loadSchedule() }
    }

    func setDayOffset(_ offset: Int) {
        let newDate = getDate(for: offset)

        if !Calendar.school.isDate(newDate, inSameDayAs: selectedDate) {
            self.selectedDate = newDate

            if !currentWeek.contains(where: { Calendar.school.isDate($0, inSameDayAs: newDate) }) {
                generateWeek(for: newDate)
                Task { await loadSchedule() }
            }
        }
    }

    private func dateKey(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    func loadSchedule() async {
        guard let startOfWeek = currentWeek.first, let endOfWeek = currentWeek.last else { return }

        let calendar = Calendar.school
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfWeek) ?? endOfWeek

        let d1 = startOfWeek.timeIntervalSince1970 * 1000
        let d2 = endOfDay.timeIntervalSince1970 * 1000

        do {

            let response = try await api.getPrsDiary(d1: d1, d2: d2)

            let currentTeacherCacheSnapshot = self.teacherCache

            let result = await Task.detached(priority: .userInitiated) { () -> ProcessingResult in

                let taskFormatter = DateFormatter()
                taskFormatter.dateFormat = "yyyy-MM-dd"

                var marksMap: [Int: (val: String, desc: String, partID: Int?)] = [:]
                if let users = response.user {
                    for user in users {
                        if let userMarks = user.mark {
                            for m in userMarks {
                                if let lid = m.lessonID, let val = m.value {
                                    marksMap[lid] = (val, m.partType ?? "Оценка", m.partID)
                                }
                            }
                        }
                    }
                }

                var batchLessons: [String: [LessonViewModel]] = [:]
                var newTeachers: [String: (short: String, full: String)] = [:]

                if let rawLessons = response.lesson {

                    for raw in rawLessons {
                        if let name = raw.unit?.name, let teacher = raw.teacher {
                            let short = teacher.shortName
                            if !short.isEmpty && short != "Учитель" {
                                newTeachers[name] = (short, teacher.fullName)
                            }
                        }
                    }

                    for raw in rawLessons {
                        guard let dateTs = raw.date, let lessonId = raw.id else { continue }

                        let date = Date(timeIntervalSince1970: dateTs / 1000)
                        let key = taskFormatter.string(from: date)

                        var hwText = ""
                        var deadLine: Double?
                        var markWeight: Double?
                        var hwFiles: [HomeworkFile] = []

                        let markInfo = marksMap[lessonId]

                        if let parts = raw.part {
                            for part in parts {

                                if part.cat == "DZ", let variants = part.variant {
                                    for v in variants {
                                        if let txt = v.text {
                                            let clean = txt.strippingHTML()
                                            if !clean.isEmpty {
                                                hwText = clean
                                                deadLine = v.deadLine
                                            }
                                        }
                                        if let files = v.file, let varId = v.id {
                                            for f in files {
                                                if let fid = f.id, let fname = f.fileName {
                                                    hwFiles.append(HomeworkFile(id: fid, name: fname, variantId: varId))
                                                }
                                            }
                                        }
                                    }
                                }

                                if markInfo?.partID != nil {
                                    if let wt = part.mrkWt {
                                        markWeight = wt
                                    }
                                }
                            }
                        }

                        let num = raw.numInDay ?? 0
                        let times = DiaryViewModel.getLessonTimesStatic(num: num)

                        let subjectName = raw.unit?.name ?? "Предмет"
                        var tShort = raw.teacher?.shortName ?? ""
                        var tFull = raw.teacher?.fullName ?? ""

                        if (tShort.isEmpty || tShort == "Учитель") {

                            if let found = newTeachers[subjectName] {
                                tShort = found.short
                                tFull = found.full
                            } else if let cached = currentTeacherCacheSnapshot[subjectName] {
                                tShort = cached.short
                                tFull = cached.full
                            }
                        }

                        let vm = LessonViewModel(
                            id: lessonId,
                            num: num,
                            subject: subjectName,
                            topic: raw.subject ?? "",
                            teacher: tShort,
                            teacherFull: tFull,
                            homework: hwText,
                            homeworkDeadline: deadLine,
                            homeworkFiles: hwFiles,
                            mark: markInfo?.val,
                            markDescription: markInfo?.desc,
                            markWeight: markWeight,
                            startTime: times.start,
                            endTime: times.end
                        )

                        if batchLessons[key] == nil { batchLessons[key] = [] }
                        batchLessons[key]?.append(vm)
                    }
                }

                for (key, list) in batchLessons {
                    batchLessons[key] = list.sorted { $0.num < $1.num }
                }

                return ProcessingResult(lessons: batchLessons, newTeachers: newTeachers)
            }.value

            self.teacherCache.merge(result.newTeachers) { (_, new) in new }
            self.lessons.merge(result.lessons) { (_, new) in new }

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func getDate(for offset: Int) -> Date {
        return Calendar.school.date(byAdding: .day, value: offset, to: baseDate) ?? baseDate
    }

    func getLessons(for date: Date) -> [LessonViewModel] {
        return lessons[dateKey(date)] ?? []
    }

    nonisolated private static func getLessonTimesStatic(num: Int) -> (start: String, end: String) {
        switch num {
        case 1: return ("09:00", "09:45")
        case 2: return ("10:00", "10:45")
        case 3: return ("11:00", "11:45")
        case 4: return ("12:00", "12:45")
        case 5: return ("13:00", "13:45")
        case 6: return ("14:00", "14:45")
        case 7: return ("15:00", "15:45")
        default: return ("", "")
        }
    }
}

struct DiaryView: View {
    @StateObject private var viewModel = DiaryViewModel()
    @State private var showCalendar = false
    @State private var selectedLesson: LessonViewModel?

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: 0) {

                    HStack {
                        Button(action: { viewModel.changeWeek(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .padding()
                        }

                        Button(action: { showCalendar = true }) {
                            HStack {
                                Image(systemName: "calendar")
                                Text(viewModel.selectedDate, format: .dateTime.month().year())
                                    .font(.headline)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(AppColors.card)
                            .cornerRadius(10)
                        }
                        .sheet(isPresented: $showCalendar) {
                            VStack {
                                DatePicker("Выберите дату", selection: $viewModel.selectedDate, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .padding()
                                    .onChange(of: viewModel.selectedDate) {
                                        viewModel.jumpToDate(viewModel.selectedDate)
                                        showCalendar = false
                                    }
                            }
                            .presentationDetents([.medium])
                        }

                        Button(action: { viewModel.changeWeek(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .padding()
                        }
                    }
                    .padding(.bottom, 4)

                    WeekStripView(week: viewModel.currentWeek, selectedDate: viewModel.selectedDate) { date in
                        viewModel.jumpToDate(date)
                    }
                    .padding(.vertical, 10)
                    .background(AppColors.card)

                    TabView(selection: $viewModel.dayOffset) {
                        ForEach(-400...400, id: \.self) { offset in
                            let date = viewModel.getDate(for: offset)
                            LessonListView(
                                date: date,
                                lessons: viewModel.getLessons(for: date),
                                onLessonTap: { lesson in
                                    selectedLesson = lesson
                                }
                            )
                            .tag(offset)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onChange(of: viewModel.dayOffset) {
                        viewModel.setDayOffset(viewModel.dayOffset)
                    }
                }
            }
            .navigationTitle("Дневник")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedLesson) { lesson in
                LessonDetailView(lesson: lesson)
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await viewModel.loadSchedule()
        }
    }
}

struct LessonListView: View, Equatable {
    let date: Date
    let lessons: [LessonViewModel]
    let onLessonTap: (LessonViewModel) -> Void

    static func == (lhs: LessonListView, rhs: LessonListView) -> Bool {
        return lhs.date == rhs.date && lhs.lessons.map { $0.id } == rhs.lessons.map { $0.id }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if lessons.isEmpty {
                    VStack {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.3))
                            .padding(.bottom, 10)
                        Text("Нет уроков")
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 50)
                } else {
                    let grouped = Dictionary(grouping: lessons, by: { $0.num })
                    let sortedNums = grouped.keys.sorted()

                    ForEach(sortedNums, id: \.self) { num in
                        if let groupLessons = grouped[num] {
                            LessonGroupRow(lessons: groupLessons, onLessonTap: onLessonTap)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct WeekStripView: View {
    let week: [Date]
    let selectedDate: Date
    let onSelect: (Date) -> Void

    private let calendar = Calendar.school
    private let days = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)

                Button(action: { onSelect(date) }) {
                    VStack(spacing: 8) {
                        Text(days[index])
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(isSelected ? AppColors.primary : .gray)

                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(AppColors.primary)
                                    .frame(width: 36, height: 36)
                            } else if isToday {
                                Circle()
                                    .stroke(AppColors.primary, lineWidth: 2)
                                    .frame(width: 36, height: 36)
                            }

                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isSelected ? .white : AppColors.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

struct LessonGroupRow: View {
    let lessons: [LessonViewModel]
    let onLessonTap: (LessonViewModel) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let first = lessons.first {
                VStack(spacing: 4) {
                    Text("\(first.num)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppColors.primary)
                        .frame(width: 30, height: 30)
                        .background(AppColors.primary.opacity(0.1))
                        .clipShape(Circle())

                    if !first.startTime.isEmpty {
                        Text(first.startTime)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 2)
            }

            VStack(spacing: 12) {
                ForEach(lessons) { lesson in
                    LessonContent(lesson: lesson)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onLessonTap(lesson)
                        }

                    if lesson.id != lessons.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(AppColors.card)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
    }
}

struct LessonContent: View {
    let lesson: LessonViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lesson.subject)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if let mark = lesson.mark {
                    Text(mark)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 24)
                        .background(getMarkColor(mark))
                        .cornerRadius(6)
                }
            }

            if !lesson.topic.isEmpty {
                Text(lesson.topic)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            if !lesson.teacher.isEmpty {
                Label(lesson.teacher, systemImage: "person")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            if !lesson.homework.isEmpty || !lesson.homeworkFiles.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "house")
                        .font(.caption)
                        .foregroundColor(AppColors.primary)
                        .padding(.top, 2)
                    Text("ДЗ")
                        .font(.caption.bold())
                        .foregroundColor(AppColors.textPrimary)
                    if !lesson.homeworkFiles.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(6)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(6)
            }
        }
    }

    func getMarkColor(_ mark: String) -> Color {
        switch mark {
        case "5": return AppColors.success
        case "4": return AppColors.primary
        case "3": return AppColors.warning
        case "2", "1": return AppColors.danger
        default: return .gray
        }
    }
}

struct LessonDetailView: View {
    let lesson: LessonViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showFullHomework = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 5) {
                        Text(lesson.subject)
                            .font(.title)
                            .bold()
                        Text("Урок №\(lesson.num) • \(lesson.startTime) - \(lesson.endTime)")
                            .foregroundColor(.gray)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 15) {
                        DetailRow(icon: "person.fill", title: "Учитель", value: lesson.teacherFull)
                        DetailRow(icon: "doc.text.fill", title: "Тема", value: lesson.topic)

                        if let mark = lesson.mark {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(AppColors.warning)
                                VStack(alignment: .leading) {
                                    Text("Оценка")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    HStack {
                                        Text(mark)
                                            .font(.title3.bold())
                                            .padding(5)
                                            .background(getMarkColor(mark).opacity(0.2))
                                            .cornerRadius(5)

                                        VStack(alignment: .leading) {
                                            if let desc = lesson.markDescription {
                                                Text(desc)
                                                    .foregroundColor(AppColors.textPrimary)
                                            }
                                            if let weight = lesson.markWeight {
                                                Text("Вес: \(String(format: "%.1f", weight))")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !lesson.homework.isEmpty || !lesson.homeworkFiles.isEmpty {
                        Button(action: { showFullHomework = true }) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "house.fill")
                                    Text("Домашнее задание")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                }
                                .foregroundColor(AppColors.primary)

                                if !lesson.homework.isEmpty {
                                    Text(lesson.homework)
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }

                                if !lesson.homeworkFiles.isEmpty {
                                    HStack {
                                        Image(systemName: "paperclip")
                                        Text("\(lesson.homeworkFiles.count) файл(ов)")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(AppColors.card)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppColors.primary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .background(AppColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $showFullHomework) {
                HomeworkDetailView(text: lesson.homework, deadline: lesson.homeworkDeadline, files: lesson.homeworkFiles)
            }
        }
        .navigationViewStyle(.stack)
    }

    func getMarkColor(_ mark: String) -> Color {
        switch mark {
        case "5": return AppColors.success
        case "4": return AppColors.primary
        case "3": return AppColors.warning
        case "2", "1": return AppColors.danger
        default: return .gray
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundColor(AppColors.primary)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .foregroundColor(AppColors.textPrimary)
            }
        }
    }
}

struct HomeworkDetailView: View {
    let text: String
    let deadline: Double?
    let files: [HomeworkFile]

    @Environment(\.presentationMode) var presentationMode
    @State private var previewURL: URL?
    @State private var isDownloading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    if let dl = deadline {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.red)
                            Text("Выполнить до: \(Date(timeIntervalSince1970: dl / 1000), style: .date)")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }

                    if !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .foregroundColor(AppColors.textPrimary)
                            .textSelection(.enabled)
                            .padding()
                            .background(AppColors.card)
                            .cornerRadius(12)
                    }

                    if !files.isEmpty {
                        Text("Вложения")
                            .font(.headline)
                            .padding(.leading, 4)

                        ForEach(files) { file in
                            Button(action: { downloadAndPreview(file) }) {
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.blue)
                                    Text(file.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "eye")
                                        .foregroundColor(.blue)
                                }
                                .padding()
                                .background(AppColors.card)
                                .cornerRadius(10)
                            }
                        }
                    }

                    if isDownloading {
                        ProgressView("Загрузка файла...")
                            .padding()
                    }

                    Spacer()
                }
                .padding()
            }
            .background(AppColors.background)
            .navigationTitle("Домашнее задание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .quickLookPreview($previewURL)
        }
        .navigationViewStyle(.stack)
    }

    func downloadAndPreview(_ file: HomeworkFile) {
        guard !isDownloading else { return }
        isDownloading = true

        let urlStr = "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/\(file.variantId)/\(file.id)"

        Task {
            do {
                let localURL = try await APIService.shared.downloadFile(endpoint: urlStr)
                await MainActor.run {
                    self.previewURL = localURL
                    self.isDownloading = false
                }
            } catch {
                print("Download error: \(error)")
                await MainActor.run {
                    self.isDownloading = false
                }
            }
        }
    }
}
