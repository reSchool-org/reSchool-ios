import SwiftUI

enum DirectoryRowType {
    case group(GroupsTreeItem)
    case user(GroupsTreeUser)
}

struct DirectoryRow: Identifiable {
    let id = UUID()
    let type: DirectoryRowType

    var name: String {
        switch type {
        case .group(let g):
            return g.groupName ?? g.groupTypeName ?? g.orgName ?? "Unknown"
        case .user(let u):
            return u.fio ?? "Unknown User"
        }
    }

    var icon: String {
        switch type {
        case .group(let g):
            if g.orgName != nil { return "building.2" }
            return "folder"
        case .user:
            return "person"
        }
    }
}

@MainActor
class DirectoryViewModelV2: ObservableObject {
    private let api = APIService.shared

    @Published var currentRows: [DirectoryRow] = []
    @Published var breadcrumbs: [String] = ["Корень"]
    @Published var isLoading = false

    @Published var searchQuery = ""
    @Published var searchResults: [UserSearchItem] = []
    @Published var isSearching = false
    private var searchTask: Task<Void, Never>?

    private var history: [[DirectoryRow]] = []

    func load() async {
        isLoading = true
        do {
            let items = try await api.getGroupsTree()
            let rows = items.map { DirectoryRow(type: .group($0)) }
            currentRows = rows
            history = []
        } catch {
            print(error)
        }
        isLoading = false
    }

    func performSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        isLoading = true

        searchTask = Task {
            do {

                try await Task.sleep(nanoseconds: 500_000_000)
                let results = try await api.searchUsers(query: searchQuery)

                if !Task.isCancelled {
                    self.searchResults = results
                    self.isLoading = false
                }
            } catch {
                print("Search error: \(error)")
                if !Task.isCancelled {
                    self.isLoading = false
                }
            }
        }
    }

    func select(row: DirectoryRow) -> GroupsTreeUser? {
        switch row.type {
        case .group(let item):

            var newRows: [DirectoryRow] = []

            if let groups = item.groups {
                newRows.append(contentsOf: groups.map { DirectoryRow(type: .group($0)) })
            }
            if let users = item.users {
                newRows.append(contentsOf: users.map { DirectoryRow(type: .user($0)) })
            }

            if !newRows.isEmpty {
                history.append(currentRows)
                currentRows = newRows
                breadcrumbs.append(row.name)
            }
            return nil

        case .user(let user):
            return user
        }
    }

    func back() {
        if let prev = history.popLast() {
            currentRows = prev
            breadcrumbs.removeLast()
        }
    }

    var canGoBack: Bool { !history.isEmpty }
}

struct SchoolDirectoryView: View {
    @StateObject private var viewModel = DirectoryViewModelV2()
    @State private var selectedUser: UserSearchItem?
    @State private var showChatParams = false
    @State private var chatThreadId: Int?
    @State private var navigateToChat = false

    var body: some View {
        NavigationStack {
            VStack {
                if !viewModel.isSearching {

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.breadcrumbs.indices, id: \.self) { idx in
                                Text(viewModel.breadcrumbs[idx])
                                    .foregroundColor(idx == viewModel.breadcrumbs.count - 1 ? .black : .blue)
                                    .onTapGesture {

                                    }
                                if idx < viewModel.breadcrumbs.count - 1 {
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color.gray.opacity(0.1))
                }

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    List {
                        if viewModel.isSearching {
                            ForEach(viewModel.searchResults) { user in
                                Button(action: {
                                    self.selectedUser = user
                                    self.showChatParams = true
                                }) {
                                    UserRow(user: user)
                                }
                            }
                        } else {
                            ForEach(viewModel.currentRows) { row in
                                Button(action: {
                                    if let groupUser = viewModel.select(row: row) {

                                        self.selectedUser = UserSearchItem(
                                            prsId: groupUser.prsId,
                                            fio: groupUser.fio,
                                            groupName: nil,
                                            isStudent: nil,
                                            isEmp: nil,
                                            isParent: nil,
                                            imageId: nil,
                                            pos: groupUser.pos?.map { UserPosition(posTypeName: $0.posTypeName) }
                                        )
                                        self.showChatParams = true
                                    }
                                }) {
                                    DirectoryRowView(row: row)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Справочник")
            .searchable(text: $viewModel.searchQuery, prompt: "Поиск людей...")
            .onChange(of: viewModel.searchQuery) { _, _ in
                viewModel.performSearch()
            }
            .toolbar {
                if viewModel.canGoBack && !viewModel.isSearching {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: viewModel.back) {
                            Image(systemName: "chevron.left")
                            Text("Назад")
                        }
                    }
                }
            }
            .actionSheet(isPresented: $showChatParams) {
                ActionSheet(
                    title: Text(selectedUser?.fio ?? "Пользователь"),
                    buttons: [
                        .default(Text("Написать сообщение")) {
                            startChat()
                        },
                        .cancel()
                    ]
                )
            }
            .navigationDestination(isPresented: $navigateToChat) {
                if let id = chatThreadId {
                    ChatDetailView(
                        threadId: id,
                        title: selectedUser?.fio ?? "Чат",
                        isGroup: false,
                        partnerImageId: selectedUser?.imageId,
                        partnerImgObjType: "USER_PICTURE",
                        partnerImgObjId: selectedUser?.prsId
                    )
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    func startChat() {
        guard let user = selectedUser, let prsId = user.prsId else { return }
        Task {
            do {
                let threadId = try await APIService.shared.saveThread(interlocutorId: prsId)
                self.chatThreadId = threadId
                self.navigateToChat = true
            } catch {
                print("Error starting chat: \(error)")
            }
        }
    }
}

struct DirectoryRowView: View {
    let row: DirectoryRow

    var body: some View {
        HStack {
            Image(systemName: row.icon)
                .foregroundColor(AppColors.primary)
                .font(.title3)
                .frame(width: 30)

            Text(row.name)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            if case .group = row.type {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct UserRow: View {
    let user: UserSearchItem

    var body: some View {
        HStack(spacing: 12) {

            GenericAsyncAvatar(
                imageId: user.imageId,
                imgObjType: "USER_PICTURE",
                imgObjId: user.prsId,
                fallbackText: String(user.fio?.prefix(1) ?? "?")
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.fio ?? "Без имени")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                HStack {
                    if let group = user.groupName {
                        Text(group)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    if let pos = user.pos?.first?.posTypeName {
                        Text(pos)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
