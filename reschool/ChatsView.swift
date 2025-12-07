import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct ChatsView: View {
    @StateObject private var api = APIService.shared
    @State private var threads: [ThreadResponse] = []
    @State private var previewThread: ThreadResponse?

    @State private var navThreadId: Int?
    @State private var navThreadTitle: String = ""
    @State private var navIsGroup = false
    @State private var navImageId: Int?
    @State private var navImgObjType: String?
    @State private var navImgObjId: Int?
    @State private var isNavigating = false

    @State private var searchText = ""
    @State private var foundUsers: [UserSearchItem] = []
    @State private var isSearchingRemote = false
    @State private var showCreateGroup = false
    private let searchDebounce = 0.5

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                List {

                    if !searchText.isEmpty {
                        Section("Глобальный поиск") {
                            if isSearchingRemote {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            } else if foundUsers.isEmpty {
                                Text("Никого не найдено")
                                    .foregroundColor(.gray)
                            } else {
                                ForEach(foundUsers) { user in
                                    Button(action: { openUserChat(user) }) {
                                        UserSearchRow(user: user)
                                    }
                                }
                            }
                        }
                    }

                    Section(searchText.isEmpty ? "Чаты" : "Найденные чаты") {
                        ForEach(filteredThreads, id: \.threadId) { thread in
                            ChatRow(thread: thread, title: getThreadTitle(thread))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openThread(thread)
                                }
                                .onLongPressGesture {
                                    withAnimation(.spring()) {
                                        previewThread = thread
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)

                if let thread = previewThread {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation {
                                    previewThread = nil
                                }
                            }

                        ChatPreviewModal(thread: thread, title: getThreadTitle(thread)) {
                            withAnimation {
                                previewThread = nil
                            }
                        }
                        .padding(24)
                        .transition(.scale.combined(with: .opacity))
                    }
                    .zIndex(100)
                }
            }
            .navigationTitle("Сообщения")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateGroup = true }) {
                        Image(systemName: "person.3.fill")
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                GroupCreationView { newThreadId, subject in

                    Task {
                        do { threads = try await api.getThreads() } catch {}
                        await MainActor.run {
                            navThreadId = newThreadId
                            navThreadTitle = subject
                            navIsGroup = true
                            navImageId = nil
                            navImgObjType = nil
                            navImgObjId = nil
                            isNavigating = true
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Поиск чатов и людей...")
            .onChange(of: searchText) { _, newValue in
                Task {
                    await performRemoteSearch(query: newValue)
                }
            }
            .navigationDestination(isPresented: $isNavigating) {
                ChatDetailView(
                    threadId: navThreadId ?? 0,
                    title: navThreadTitle,
                    isGroup: navIsGroup,
                    partnerImageId: navImageId,
                    partnerImgObjType: navImgObjType,
                    partnerImgObjId: navImgObjId
                )
            }
        }
        .task {
            do { threads = try await api.getThreads() } catch {}
        }
    }

    var filteredThreads: [ThreadResponse] {
        if searchText.isEmpty {
            return threads
        } else {
            return threads.filter { thread in
                let title = getThreadTitle(thread)
                return title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    func getThreadTitle(_ thread: ThreadResponse) -> String {
        if let subject = thread.subject, !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subject
        }
        return thread.senderFio ?? "Без темы"
    }

    func openThread(_ thread: ThreadResponse) {
        navThreadId = thread.threadId
        navThreadTitle = getThreadTitle(thread)
        navIsGroup = (thread.dlgType == 2)
        navImageId = thread.imageId
        navImgObjType = thread.imgObjType
        navImgObjId = thread.imgObjId
        isNavigating = true
    }

    func openUserChat(_ user: UserSearchItem) {
        guard let prsId = user.prsId else { return }
        Task {
            do {
                let tid = try await api.saveThread(interlocutorId: prsId)
                await MainActor.run {
                    navThreadId = tid
                    navThreadTitle = user.fio ?? "Чат"
                    navIsGroup = false
                    navImageId = user.imageId
                    navImgObjType = "USER_PICTURE"
                    navImgObjId = user.prsId
                    isNavigating = true
                }
            } catch {
                print("Error creating chat: \(error)")
            }
        }
    }

    private var searchTask: Task<Void, Never>?

    func performRemoteSearch(query: String) async {

        guard !query.isEmpty else {
            foundUsers = []
            isSearchingRemote = false
            return
        }

        isSearchingRemote = true
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            if query != searchText { return }

            let results = try await api.searchUsers(query: query)
            if query == searchText {
                foundUsers = results
                isSearchingRemote = false
            }
        } catch {
            if query == searchText {
                isSearchingRemote = false
            }
        }
    }
}

struct ChatRow: View {
    let thread: ThreadResponse
    let title: String

    var body: some View {
        HStack(spacing: 15) {
            GenericAsyncAvatar(
                imageId: thread.imageId,
                imgObjType: thread.imgObjType,
                imgObjId: thread.imgObjId,
                fallbackText: String(thread.senderFio?.prefix(1) ?? "?")
            )
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text(thread.msgPreview?.strippingHTML() ?? "")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct UserSearchRow: View {
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
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ChatPreviewModal: View {
    let thread: ThreadResponse
    let title: String
    let onClose: () -> Void

    @State private var messages: [MessageResponse] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 20) {

            HStack {
                GenericAsyncAvatar(
                    imageId: thread.imageId,
                    imgObjType: thread.imgObjType,
                    imgObjId: thread.imgObjId,
                    fallbackText: String(thread.senderFio?.prefix(1) ?? "?")
                )
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .bold()
                        .foregroundColor(AppColors.textPrimary)

                    if let sender = thread.senderFio {
                        Text(sender)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Text(Date(timeIntervalSince1970: thread.sendDate / 1000), style: .date)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }

            Divider()

            ZStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                if messages.isEmpty {
                                    Text("Нет сообщений")
                                        .foregroundColor(.gray)
                                        .padding(.top, 20)
                                } else {
                                    ForEach(messages.indices, id: \.self) { idx in
                                        let msg = messages[idx]
                                        let isMe = isMessageMine(msg)
                                        let isFirstInSequence = isFirstMessageInSequence(idx: idx)

                                        HStack(alignment: .bottom, spacing: 8) {
                                            if isMe { Spacer() }

                                            if !isMe {
                                                if isFirstInSequence {
                                                    GenericAsyncAvatar(
                                                        imageId: nil,
                                                        imgObjType: "USER_PICTURE",
                                                        imgObjId: msg.senderId,
                                                        fallbackText: String(msg.senderFio?.prefix(1) ?? "?")
                                                    )
                                                    .frame(width: 32, height: 32)
                                                } else {
                                                    Color.clear.frame(width: 32, height: 32)
                                                }
                                            }

                                            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                                                if !isMe && isFirstInSequence {
                                                    Text(msg.senderFio ?? "Неизвестный")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                        .padding(.leading, 4)
                                                }

                                                HStack(alignment: .bottom, spacing: 6) {
                                                    Text(msg.msg?.strippingHTML() ?? "")
                                                        .foregroundColor(isMe ? .white : AppColors.textPrimary)
                                                        .font(.system(size: 14))

                                                    Text(Date(timeIntervalSince1970: msg.createDate / 1000), style: .time)
                                                        .font(.system(size: 10))
                                                        .foregroundColor(isMe ? .white.opacity(0.7) : .gray)
                                                }
                                                .padding(10)
                                                .background(isMe ? AppColors.primary : AppColors.background)
                                                .cornerRadius(12)
                                            }

                                            if !isMe { Spacer() }
                                        }
                                        .id(idx)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 10)
                        }
                        .frame(maxHeight: 400)
                        .onAppear {
                            if !messages.isEmpty {
                                proxy.scrollTo(messages.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppColors.card)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppColors.primary.opacity(0.2), lineWidth: 1)
        )
        .task {
            await loadMessages()
        }
    }

    func loadMessages() async {
        do {
            isLoading = true
            let fetched = try await APIService.shared.getMessages(threadId: thread.threadId)
            messages = fetched.reversed()
            isLoading = false
        } catch {
            print("Preview load error: \(error)")
            isLoading = false
        }
    }

    func isMessageMine(_ msg: MessageResponse) -> Bool {
        if let myName = APIService.shared.userProfile?.fullName,
           let senderName = msg.senderFio {
            return myName == senderName
        }
        return false
    }

    func isFirstMessageInSequence(idx: Int) -> Bool {
        if idx == 0 { return true }
        let currentMsg = messages[idx]
        let prevMsg = messages[idx - 1]
        return currentMsg.senderFio != prevMsg.senderFio
    }
}

struct GroupCreationView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var api = APIService.shared

    @State private var subject = ""
    @State private var searchText = ""
    @State private var searchResults: [UserSearchItem] = []
    @State private var selectedUsers: [UserSearchItem] = []
    @State private var isCreating = false
    @State private var isSearching = false

    var onGroupCreated: ((Int, String) -> Void)?

    var body: some View {
        NavigationView {
            VStack {

                TextField("Название группы", text: $subject)
                    .padding()
                    .background(AppColors.card)
                    .cornerRadius(10)
                    .padding()

                if !selectedUsers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selectedUsers) { user in
                                ChipView(text: user.fio ?? "", onRemove: {
                                    selectedUsers.removeAll(where: { $0.id == user.id })
                                })
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 50)
                }

                TextField("Поиск участников...", text: $searchText)
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .onChange(of: searchText) { _, query in
                        Task { await performSearch(query) }
                    }

                List(searchResults) { user in
                    Button(action: {
                        if !selectedUsers.contains(where: { $0.id == user.id }) {
                            selectedUsers.append(user)
                            searchText = ""
                            searchResults = []
                        }
                    }) {
                        HStack {
                            GenericAsyncAvatar(
                                imageId: user.imageId,
                                imgObjType: "USER_PICTURE",
                                imgObjId: user.prsId,
                                fallbackText: String(user.fio?.prefix(1) ?? "?")
                            )
                            .frame(width: 32, height: 32)

                            Text(user.fio ?? "")
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            if selectedUsers.contains(where: { $0.id == user.id }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Создать") { createGroup() }
                        .disabled(subject.isEmpty || selectedUsers.isEmpty || isCreating)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            if query != searchText { return }

            let results = try await api.searchUsers(query: query)
            if query == searchText {
                searchResults = results
                isSearching = false
            }
        } catch {
            isSearching = false
        }
    }

    func createGroup() {
        isCreating = true
        Task {
            do {
                let threadId = try await api.createGroupChat(subject: subject)
                if threadId != 0 {
                    try await api.setGroupMembers(threadId: threadId, members: selectedUsers)
                    await MainActor.run {
                        isCreating = false
                        presentationMode.wrappedValue.dismiss()
                        onGroupCreated?(threadId, subject)
                    }
                }
            } catch {
                print("Group creation failed: \(error)")
                isCreating = false
            }
        }
    }
}

struct ChipView: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding(8)
        .background(AppColors.card)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ChatDetailView: View {
    let threadId: Int
    let title: String
    let isGroup: Bool
    let partnerImageId: Int?
    let partnerImgObjType: String?
    let partnerImgObjId: Int?

    @StateObject private var api = APIService.shared
    @State private var messages: [MessageResponse] = []
    @State private var newMessage = ""
    @State private var isSending = false

    @Environment(\.presentationMode) var presentationMode
    @State private var showLeaveAlert = false

    @State private var isSelectionMode = false
    @State private var selectedMessageIds = Set<Int>()

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedFiles: [UploadFile] = []
    @State private var showFileImporter = false

    @State private var previewURL: URL?
    @State private var isDownloading = false

    var body: some View {
        VStack {
            if isDownloading {
                HStack {
                    Text("Загрузка файла...")
                        .font(.caption)
                    ProgressView()
                }
                .padding(4)
                .background(Material.regular)
                .cornerRadius(8)
                .padding(.top, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages.indices, id: \.self) { idx in
                            let msg = messages[idx]
                            let isMe = isMessageMine(msg)
                            let isFirstInSequence = isFirstMessageInSequence(idx: idx)
                            let msgId = msg.id

                            HStack(alignment: .bottom, spacing: 8) {

                                if isSelectionMode {
                                    Image(systemName: selectedMessageIds.contains(msgId) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedMessageIds.contains(msgId) ? AppColors.primary : .gray)
                                        .font(.title2)
                                        .onTapGesture {
                                            toggleSelection(for: msgId)
                                        }
                                }

                                if isMe { Spacer() }

                                if !isMe {
                                    if isFirstInSequence {
                                        avatarView(for: msg)
                                            .frame(width: 32, height: 32)
                                    } else {
                                        Color.clear.frame(width: 32, height: 32)
                                    }
                                }

                                VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                                    if !isMe && isFirstInSequence {
                                        Text(msg.senderFio ?? "Неизвестный")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .padding(.leading, 4)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        if let attachments = msg.attachInfo, !attachments.isEmpty {
                                            ForEach(attachments, id: \.fileId) { attach in
                                                AttachmentView(attachment: attach, isMe: isMe) {
                                                    downloadAndPreview(attach, msgId: msg.msgId ?? 0)
                                                }
                                            }
                                        }

                                        HStack(alignment: .bottom, spacing: 6) {
                                            Text(msg.msg?.strippingHTML() ?? "")
                                                .foregroundColor(isMe ? .white : AppColors.textPrimary)

                                            Text(Date(timeIntervalSince1970: msg.createDate / 1000), style: .time)
                                                .font(.system(size: 10))
                                                .foregroundColor(isMe ? .white.opacity(0.7) : .gray)
                                        }
                                    }
                                    .padding(10)
                                    .background(isMe ? AppColors.primary : AppColors.card)
                                    .cornerRadius(16)
                                    .shadow(radius: 1)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelectionMode {
                                            toggleSelection(for: msgId)
                                        }
                                    }
                                    .contextMenu {
                                        if !isSelectionMode {
                                            Button {
                                                UIPasteboard.general.string = msg.msg?.strippingHTML()
                                            } label: {
                                                Label("Скопировать", systemImage: "doc.on.doc")
                                            }

                                            Button {
                                                withAnimation {
                                                    isSelectionMode = true
                                                    selectedMessageIds.insert(msgId)
                                                }
                                            } label: {
                                                Label("Выделить", systemImage: "checkmark.circle")
                                            }
                                        }
                                    }
                                }

                                if !isMe { Spacer() }
                            }
                            .padding(.horizontal)
                            .id(idx)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        if !messages.isEmpty {
                            withAnimation {
                                proxy.scrollTo(messages.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if isSelectionMode {
                ChatSelectionBar(
                    isSelectionMode: $isSelectionMode,
                    selectedMessageIds: $selectedMessageIds,
                    copySelectedMessages: copySelectedMessages
                )
            } else {
                ChatInputBar(
                    newMessage: $newMessage,
                    selectedItems: $selectedItems,
                    selectedFiles: $selectedFiles,
                    showFileImporter: $showFileImporter,
                    isSending: $isSending,
                    sendMessage: sendMessage
                )
            }
        }
        .quickLookPreview($previewURL)
        .navigationTitle(title)
        .background(AppColors.background)
        .toolbar {
            if isGroup && !isSelectionMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive, action: {
                            showLeaveAlert = true
                        }) {
                            Label("Покинуть чат", systemImage: "door.left.hand.open")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Покинуть чат?", isPresented: $showLeaveAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Покинуть", role: .destructive) {
                leaveChat()
            }
        } message: {
            Text("Вы уверены, что хотите покинуть этот чат?")
        }
        .task {
            await loadMessages()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            handleFileImport(result)
        }
        .onChange(of: selectedItems) { _, _ in
            processSelectedPhotos()
        }
    }

    func loadMessages() async {
        do {
            messages = try await api.getMessages(threadId: threadId).reversed()
        } catch {}
    }

    func sendMessage() {
        guard !newMessage.isEmpty || !selectedFiles.isEmpty else { return }
        isSending = true
        let textToSend = newMessage
        let filesToSend = selectedFiles

        Task {
            do {
                _ = try await api.sendMessage(threadId: threadId, msgText: textToSend, files: filesToSend)
                await MainActor.run {
                    newMessage = ""
                    selectedFiles.removeAll()
                }
                await loadMessages()
            }
            catch {
                print("Error sending message: \(error)")
            }
            isSending = false
        }
    }

    func leaveChat() {
        Task {
            do {
                try await api.leaveChat(threadId: threadId)
                await MainActor.run {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            catch {
                print("Error leaving chat: \(error)")
            }
        }
    }

    func isMessageMine(_ msg: MessageResponse) -> Bool {
        if let myName = api.userProfile?.fullName,
           let senderName = msg.senderFio {
            return myName == senderName
        }
        return false
    }

    func isFirstMessageInSequence(idx: Int) -> Bool {
        if idx == 0 { return true }
        let currentMsg = messages[idx]
        let prevMsg = messages[idx - 1]
        return currentMsg.senderFio != prevMsg.senderFio
    }

    func avatarView(for msg: MessageResponse) -> some View {
        let imageId = isGroup ? nil : partnerImageId
        let imgObjType = isGroup ? "USER_PICTURE" : (partnerImgObjType ?? "USER_PICTURE")
        let imgObjId = isGroup ? msg.senderId : (partnerImgObjId ?? msg.senderId)
        let fallback = String(msg.senderFio?.prefix(1) ?? "?")

        return GenericAsyncAvatar(
            imageId: imageId,
            imgObjType: imgObjType,
            imgObjId: imgObjId,
            fallbackText: fallback
        )
    }

    func toggleSelection(for msgId: Int) {
        if selectedMessageIds.contains(msgId) {
            selectedMessageIds.remove(msgId)
        } else {
            selectedMessageIds.insert(msgId)
        }
    }

    func copySelectedMessages() {
        let selectedTexts = messages.filter { selectedMessageIds.contains($0.id) }
            .sorted { $0.createDate < $1.createDate }
            .compactMap { $0.msg?.strippingHTML() }
            .joined(separator: "\n")

        UIPasteboard.general.string = selectedTexts

        withAnimation {
            isSelectionMode = false
            selectedMessageIds.removeAll()
        }
    }

    private func processSelectedPhotos() {
        Task {
            for item in selectedItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if data.count <= 15 * 1024 * 1024 {
                        let filename = "image_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).jpg"
                        let file = UploadFile(data: data, name: filename, mimeType: "image/jpeg")
                        await MainActor.run {
                            selectedFiles.append(file)
                        }
                    }
                }
            }
            await MainActor.run {
                selectedItems.removeAll()
            }
        }
    }

    private func downloadAndPreview(_ attachment: AttachInfo, msgId: Int) {
        guard let fileId = attachment.fileId else { return }
        let endpoint = api.getAttachmentEndpoint(msgId: msgId, fileId: fileId)

        isDownloading = true
        Task {
            do {
                let url = try await api.downloadFile(endpoint: endpoint)
                await MainActor.run {
                    self.previewURL = url
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

    private func handleFileImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url)
                if data.count <= 15 * 1024 * 1024 {
                    let filename = url.lastPathComponent
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let file = UploadFile(data: data, name: filename, mimeType: mimeType)
                    selectedFiles.append(file)
                }
            }
        } catch {
            print("File import error: \(error)")
        }
    }
}

struct AttachmentView: View {
    let attachment: AttachInfo
    let isMe: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName ?? "Файл")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let size = attachment.fileSize {
                        Text(formatSize(size))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
            }
            .padding(8)
            .background(isMe ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
            .cornerRadius(8)
            .foregroundColor(isMe ? .white : .primary)
        }
    }

    private var iconName: String {
        guard let type = attachment.fileType?.lowercased() else { return "doc.fill" }
        if type.contains("image") { return "photo.fill" }
        if type.contains("pdf") { return "doc.text.fill" }
        if type.contains("zip") || type.contains("rar") { return "archivebox.fill" }
        return "doc.fill"
    }

    private func formatSize(_ size: Int) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useKB, .useMB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: Int64(size))
    }
}

struct ChatSelectionBar: View {
    @Binding var isSelectionMode: Bool
    @Binding var selectedMessageIds: Set<Int>
    var copySelectedMessages: () -> Void

    var body: some View {
        HStack {
            Button("Отмена") {
                withAnimation {
                    isSelectionMode = false
                    selectedMessageIds.removeAll()
                }
            }
            .foregroundColor(.red)

            Spacer()

            Text("Выбрано: \(selectedMessageIds.count)")
                .font(.headline)

            Spacer()

            Button(action: copySelectedMessages) {
                Image(systemName: "doc.on.doc")
            }
            .disabled(selectedMessageIds.isEmpty)
        }
        .padding()
        .background(AppColors.card)
    }
}

struct ChatInputBar: View {
    @Binding var newMessage: String
    @Binding var selectedItems: [PhotosPickerItem]
    @Binding var selectedFiles: [UploadFile]
    @Binding var showFileImporter: Bool
    @Binding var isSending: Bool
    var sendMessage: () -> Void

    @State private var showPhotoPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if !selectedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedFiles.indices, id: \.self) { idx in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.gray)
                                Text(selectedFiles[idx].name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button(action: {
                                    withAnimation {
                                        if idx < selectedFiles.count {
                                            selectedFiles.remove(at: idx)
                                        }
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }

            HStack {
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Фото", systemImage: "photo")
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Файл", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.primary)
                }

                TextField("Сообщение...", text: $newMessage)
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                    .disabled(isSending)

                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor((newMessage.isEmpty && selectedFiles.isEmpty) ? .gray : AppColors.primary)
                    }
                }
                .disabled((newMessage.isEmpty && selectedFiles.isEmpty) || isSending)
            }
            .padding()
            .background(AppColors.card)
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItems, matching: .images)
        }
    }
}