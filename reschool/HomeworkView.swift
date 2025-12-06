import SwiftUI

struct HomeworkItem: Identifiable {
    let id = UUID()
    let date: Date
    let subject: String
    let text: String
    let files: [HomeworkFile]
    let deadline: Double?
}

@MainActor
class HomeworkViewModel: ObservableObject {
    private let api = APIService.shared
    private let settings = SettingsManager.shared

    @Published var items: [HomeworkItem] = []
    @Published var isLoading = false
    @Published var error: String?

    @Published var startDate: Date
    @Published var endDate: Date

    init() {

        let now = Date()
        self.startDate = now.addingTimeInterval(Double(-settings.hwDaysPast) * 24 * 3600)
        self.endDate = now.addingTimeInterval(Double(settings.hwDaysFuture) * 24 * 3600)
    }

    func loadHomework() async {
        isLoading = true
        error = nil
        items = []

        do {
            let d1 = startDate.timeIntervalSince1970 * 1000
            let d2 = endDate.timeIntervalSince1970 * 1000

            let response = try await api.getPrsDiary(d1: d1, d2: d2)

            var newItems: [HomeworkItem] = []

            if let lessons = response.lesson {
                for lesson in lessons {
                    guard let dateTs = lesson.date,
                          let parts = lesson.part else { continue }

                    let lessonDate = Date(timeIntervalSince1970: dateTs / 1000)
                    let subject = lesson.unit?.name ?? "Предмет"

                    for part in parts {
                        if part.cat == "DZ" {
                            if let variants = part.variant {
                                for variant in variants {
                                    let rawText = variant.text ?? ""
                                    let cleanText = rawText.strippingHTML()

                                    var hwFiles: [HomeworkFile] = []
                                    if let files = variant.file, let varId = variant.id {
                                        for f in files {
                                            if let fid = f.id, let fname = f.fileName {
                                                hwFiles.append(HomeworkFile(id: fid, name: fname, variantId: varId))
                                            }
                                        }
                                    }

                                    if !cleanText.isEmpty || !hwFiles.isEmpty {
                                        newItems.append(HomeworkItem(
                                            date: lessonDate,
                                            subject: subject,
                                            text: cleanText,
                                            files: hwFiles,
                                            deadline: variant.deadLine
                                        ))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            self.items = newItems.sorted { $0.date > $1.date }

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

struct HomeworkView: View {
    @StateObject private var viewModel = HomeworkViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showDatePicker = false
    @State private var selectedItem: HomeworkItem?

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack {

                    Button(action: { showDatePicker.toggle() }) {
                        HStack {
                            Image(systemName: "calendar")
                            Text("\(formatDate(viewModel.startDate)) - \(formatDate(viewModel.endDate))")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding()
                        .background(AppColors.card)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                    }
                    .padding()
                    .sheet(isPresented: $showDatePicker) {
                        VStack {
                            Text("Выберите период")
                                .font(.headline)
                                .padding()

                            DatePicker("С", selection: $viewModel.startDate, displayedComponents: .date)
                            DatePicker("По", selection: $viewModel.endDate, displayedComponents: .date)

                            Button("Применить") {
                                showDatePicker = false
                                Task { await viewModel.loadHomework() }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                        .padding()
                        .presentationDetents([.medium])
                    }

                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else if let error = viewModel.error {
                        Spacer()
                        Text(error).foregroundColor(.red).padding()
                        Button("Повторить") { Task { await viewModel.loadHomework() } }
                        Spacer()
                    } else if viewModel.items.isEmpty {
                        Spacer()
                        Text("Нет заданий за выбранный период")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        List {
                            let grouped = Dictionary(grouping: viewModel.items) { item in
                                Calendar.current.startOfDay(for: item.date)
                            }
                            let sortedDates = grouped.keys.sorted(by: >)

                            ForEach(sortedDates, id: \.self) { date in
                                Section(header: Text(date, style: .date)) {
                                    ForEach(grouped[date] ?? []) { item in
                                        HomeworkRow(item: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedItem = item
                                            }
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await viewModel.loadHomework()
                        }
                    }
                }
            }
            .navigationTitle("Домашнее задание")
            .sheet(item: $selectedItem) { item in
                HomeworkDetailView(text: item.text, deadline: item.deadline, files: item.files)
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await viewModel.loadHomework()
        }
        .onChange(of: settings.hwDaysPast) { updateDateRange() }
        .onChange(of: settings.hwDaysFuture) { updateDateRange() }
    }

    func updateDateRange() {
        let now = Date()
        viewModel.startDate = now.addingTimeInterval(Double(-settings.hwDaysPast) * 24 * 3600)
        viewModel.endDate = now.addingTimeInterval(Double(settings.hwDaysFuture) * 24 * 3600)
        Task { await viewModel.loadHomework() }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}

struct HomeworkRow: View {
    let item: HomeworkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.subject)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
            }

            if !item.text.isEmpty {
                Text(item.text)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
            }

            if !item.files.isEmpty {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(.blue)
                    Text("\(item.files.count) вложений")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(AppColors.card)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}