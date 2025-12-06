import SwiftUI

@MainActor
class MarksViewModel: ObservableObject {
    private let api = APIService.shared
    private let settings = SettingsManager.shared

    @Published var allPeriods: [PeriodSelectionItem] = []
    @Published var selectedPeriod: PeriodSelectionItem?
    @Published var subjects: [SubjectData] = []
    @Published var isLoading = false
    @Published var error: String?

    private let savedPeriodKey = "lastSelectedPeriodId"

    struct PeriodSelectionItem: Hashable, Identifiable {
        let id = UUID()
        let period: PeriodResponse
        let groupId: Int
        let groupName: String
        let depth: Int
        let isRoot: Bool

        static func == (lhs: PeriodSelectionItem, rhs: PeriodSelectionItem) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        var displayName: String {
            let prefix = String(repeating: "  ", count: depth)
            if isRoot {
                return "\(groupName): \(period.name ?? "")"
            } else {
                return "\(prefix)\(period.name ?? "")"
            }
        }
    }

    struct SubjectData: Identifiable {
        let id: String
        let name: String
        let average: String
        let marks: [MarkData]
        let teacher: String?
        let rating: String?
    }

    struct MarkData: Identifiable {
        let id = UUID()
        let value: String
        let date: Date
        let lesson: LessonViewModel
    }

    func loadPeriods() async {
        isLoading = true
        error = nil

        do {
            var groups = try await api.getClassByUser()

            groups.sort { ($0.begDate ?? 0) > ($1.begDate ?? 0) }

            if settings.displayOnlyCurrentClass, let first = groups.first {
                groups = [first]
            }

            var items: [PeriodSelectionItem] = []

            for group in groups {
                guard let groupId = group.groupId else { continue }
                let groupName = group.groupName ?? "Group \(groupId)"

                let rootPeriod = try await api.getPeriods(groupId: groupId)

                if let children = rootPeriod.items {
                    let flatChildren = flattenPeriods(children, depth: 0)
                    items.append(contentsOf: flatChildren.map { p in
                        PeriodSelectionItem(
                            period: p.period,
                            groupId: groupId,
                            groupName: groupName,
                            depth: p.depth,
                            isRoot: false
                        )
                    })
                }
            }

            self.allPeriods = items

            if let savedId = UserDefaults.standard.integer(forKey: savedPeriodKey) as Int?,
               savedId != 0,
               let found = items.first(where: { $0.period.id == savedId }) {
                self.selectedPeriod = found
            } else {

                let now = Date().timeIntervalSince1970 * 1000
                if let current = items.first(where: { item in
                    guard let d1 = item.period.date1,
                          let d2 = item.period.date2 else { return false }
                    return now >= d1 && now <= d2
                }) {
                    self.selectedPeriod = current
                } else {
                    self.selectedPeriod = items.first
                }
            }

            if selectedPeriod != nil {
                await loadMarksData()
            }

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func flattenPeriods(_ periods: [PeriodResponse], depth: Int) -> [(period: PeriodResponse, depth: Int)] {
        var result: [(PeriodResponse, Int)] = []
        let sorted = periods.sorted { ($0.date1 ?? 0) < ($1.date1 ?? 0) }

        for p in sorted {

            let code = p.typeCode ?? ""
            let isValid = code == "Q" || code == "HY"

            if isValid {
                result.append((p, depth))
            }

            if let children = p.items {
                let nextDepth = isValid ? depth + 1 : depth
                result.append(contentsOf: flattenPeriods(children, depth: nextDepth))
            }
        }
        return result
    }

    func selectPeriod(_ item: PeriodSelectionItem) {
        selectedPeriod = item
        if let pid = item.period.id {
            UserDefaults.standard.set(pid, forKey: savedPeriodKey)
        }
        Task { await loadMarksData() }
    }

    func loadMarksData() async {
        guard let periodItem = selectedPeriod,
              let periodId = periodItem.period.id,
              let d1 = periodItem.period.date1,
              let d2 = periodItem.period.date2 else { return }

        isLoading = true

        do {

            async let unitsTask = api.getDiaryUnits(periodId: periodId)
            async let diaryTask = api.getPrsDiary(d1: d1, d2: d2)

            let (units, diary) = try await (unitsTask, diaryTask)

            var lessonMap: [Int: LessonViewModel] = [:]

            var marksByLessonId: [Int: [(val: String, date: Date?, desc: String, partID: Int?)]] = [:]

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

            if let users = diary.user {
                for user in users {
                    if let marks = user.mark {
                        for m in marks {
                            if let lid = m.lessonID, let val = m.value {
                                if marksByLessonId[lid] == nil { marksByLessonId[lid] = [] }
                                marksByLessonId[lid]?.append((val, nil, m.partType ?? "Оценка", m.partID))
                            }
                        }
                    }
                }
            }

            if let lessons = diary.lesson {
                for raw in lessons {
                    guard let lessonId = raw.id else { continue }

                    if let parts = raw.part {
                        for part in parts {
                            if let pMarks = part.mark {
                                for m in pMarks {
                                    if let val = m.markValue {
                                        var mDate: Date?
                                        if let ds = m.markDt {
                                            mDate = dateFormatter.date(from: ds)
                                        }

                                        if marksByLessonId[lessonId] == nil { marksByLessonId[lessonId] = [] }
                                        marksByLessonId[lessonId]?.append((val, mDate, part.cat ?? "Оценка", nil))
                                    }
                                }
                            }
                        }
                    }

                    var hwText = ""
                    var deadLine: Double?
                    var markWeight: Double?

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
                                }
                            }

                            if let wt = part.mrkWt {
                                markWeight = wt
                            }
                        }
                    }

                    let markInfo = marksByLessonId[lessonId]?.last

                    var tShort = raw.teacher?.shortName ?? ""
                    var tFull = raw.teacher?.fullName ?? ""

                    if tShort.isEmpty, let fio = raw.teacherFio {
                        tFull = fio

                        let parts = fio.split(separator: " ")
                        if parts.count >= 3 {
                            tShort = "\(parts[0]) \(parts[1].prefix(1)).\(parts[2].prefix(1))."
                        } else {
                            tShort = fio
                        }
                    }

                    let vm = LessonViewModel(
                        id: lessonId,
                        num: raw.numInDay ?? 0,
                        subject: raw.unit?.name ?? "Предмет",
                        topic: raw.subject ?? "",
                        teacher: tShort,
                        teacherFull: tFull,
                        homework: hwText,
                        homeworkDeadline: deadLine,
                        homeworkFiles: [],
                        mark: markInfo?.val,
                        markDescription: markInfo?.desc,
                        markWeight: markWeight,
                        startTime: "",
                        endTime: ""
                    )
                    lessonMap[lessonId] = vm
                }
            }

            var unitMarks: [Int: [MarkData]] = [: ]

            var unitTeachers: [Int: String] = [: ]

            if let lessons = diary.lesson {
                for lesson in lessons {
                    guard let lid = lesson.id,
                          let dateTs = lesson.date,
                          let uidStr = lesson.unit?.name,
                          let vm = lessonMap[lid]
                    else { continue }

                    let lessonDate = Date(timeIntervalSince1970: dateTs / 1000)

                    if let unitObj = units.first(where: { $0.unitName == uidStr }) {
                        let unitId = unitObj.unitId ?? 0

                        if unitTeachers[unitId] == nil && !vm.teacherFull.isEmpty {
                            unitTeachers[unitId] = vm.teacherFull
                        }

                        if let markList = marksByLessonId[lid] {
                            for m in markList {

                                let finalDate = m.date ?? lessonDate

                                let specificVm = vm.with(mark: m.val, description: m.desc)

                                let markData = MarkData(
                                    value: m.val,
                                    date: finalDate,
                                    lesson: specificVm
                                )

                                if unitMarks[unitId] == nil { unitMarks[unitId] = [] }
                                unitMarks[unitId]?.append(markData)
                            }
                        }
                    }
                }
            }

            self.subjects = units.map { unit in
                let unitId = unit.unitId ?? 0
                let name = unit.unitName ?? "Предмет"
                let avg = unit.overMark.map { String(format: "%.2f", $0) } ?? "-"

                let marks = (unitMarks[unitId] ?? []).sorted { $0.date < $1.date }
                let teacher = unitTeachers[unitId]
                let rating = unit.rating

                return SubjectData(
                    id: String(unitId),
                    name: name,
                    average: avg,
                    marks: marks,
                    teacher: teacher,
                    rating: rating
                )
            }

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

struct MarksView: View {
    @StateObject private var viewModel = MarksViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedLesson: LessonViewModel?
    @State private var selectedSubject: MarksViewModel.SubjectData?

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: 0) {

                    if !viewModel.allPeriods.isEmpty {
                        Menu {
                            ForEach(viewModel.allPeriods) { item in
                                Button(action: {
                                    viewModel.selectPeriod(item)
                                }) {
                                    HStack {
                                        Text(item.displayName)
                                        if viewModel.selectedPeriod == item {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(viewModel.selectedPeriod?.displayName ?? "Выберите период")
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(AppColors.primary)
                            }
                            .padding()
                            .background(AppColors.card)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 5)
                        }
                        .padding()
                    }

                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else if let error = viewModel.error {
                        Spacer()
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Повторить") {
                            Task { await viewModel.loadPeriods() }
                        }
                        Spacer()
                    } else {

                        List {
                            ForEach(viewModel.subjects) { subject in
                                makeSubjectRow(subject)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Оценки")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedLesson) { lesson in
                LessonDetailView(lesson: lesson)
            }
            .sheet(item: $selectedSubject) { subject in
                SubjectDetailView(subject: subject)
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if viewModel.allPeriods.isEmpty {
                await viewModel.loadPeriods()
            }
        }
        .onChange(of: settings.displayOnlyCurrentClass) { _, _ in
            Task { await viewModel.loadPeriods() }
        }
    }

    private func makeSubjectRow(_ subject: MarksViewModel.SubjectData) -> some View {
        SubjectMarksRow(
            subject: subject,
            onMarkTap: { lesson in
                selectedLesson = lesson
            },
            onSubjectTap: {
                selectedSubject = subject
            }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
    }
}

struct SubjectDetailView: View {
    let subject: MarksViewModel.SubjectData
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    Text(subject.name)
                        .font(.title)
                        .bold()
                        .foregroundColor(AppColors.textPrimary)

                    Divider()

                    VStack(alignment: .leading, spacing: 15) {
                        DetailRow(icon: "person.fill", title: "Преподаватель", value: subject.teacher ?? "Не указан")

                        if let rating = subject.rating {
                            DetailRow(icon: "chart.bar.fill", title: "Рейтинг в классе", value: rating)
                        } else {
                            DetailRow(icon: "chart.bar.fill", title: "Рейтинг", value: "Нет данных")
                        }

                        DetailRow(icon: "percent", title: "Средний балл", value: subject.average)
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
        }
        .navigationViewStyle(.stack)
    }
}

struct SubjectMarksRow: View {
    let subject: MarksViewModel.SubjectData
    let onMarkTap: (LessonViewModel) -> Void
    let onSubjectTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Button(action: onSubjectTap) {
                HStack {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    if subject.average != "-" {
                        Text(subject.average)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(getAvgColor(subject.average))
                            .clipShape(Capsule())
                    }
                }
            }

            if !subject.marks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        let grouped = Dictionary(grouping: subject.marks) { Calendar.current.startOfDay(for: $0.date) }
                        let sortedDates = grouped.keys.sorted()

                        ForEach(sortedDates, id: \.self) { date in
                            VStack(spacing: 6) {
                                if let marks = grouped[date] {
                                    ForEach(marks) { mark in
                                        Button(action: { onMarkTap(mark.lesson) }) {
                                            Text(mark.value)
                                                .font(.headline)
                                                .foregroundColor(AppColors.textPrimary)
                                                .frame(width: 40, height: 40)
                                                .background(getMarkColor(mark.value).opacity(0.2))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(getMarkColor(mark.value), lineWidth: 1)
                                                )
                                                .cornerRadius(8)
                                        }
                                    }
                                }

                                Text(date, format: .dateTime.day().month())
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                Text("Нет оценок")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(AppColors.card)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 2)
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

    func getAvgColor(_ avg: String) -> Color {
        guard let val = Double(avg) else { return .gray }
        if val >= 4.5 { return AppColors.success }
        if val >= 3.5 { return AppColors.primary }
        if val >= 2.5 { return AppColors.warning }
        return AppColors.danger
    }
}
