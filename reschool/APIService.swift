import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

class APIService: ObservableObject {
    static let shared = APIService()

    private let baseURL = "https://app.eschool.center/ec-server"
    private var session = URLSession.shared
    @Published var isAuthenticated = false

    private(set) var userId: Int?
    private(set) var currentPrsId: Int?
    private(set) var userProfile: Profile?

    private var cookies: [HTTPCookie] = []

    init() {
        loadSession()
    }

    private func saveSession(_ cookies: [HTTPCookie]) {
        if let sessionCookie = cookies.first(where: { $0.name == "JSESSIONID" }) {
            KeychainHelper.shared.save(sessionCookie.value, service: "reschool-app", account: "session-cookie")
        }
    }

    private func loadSession() {
        if let value = KeychainHelper.shared.readString(service: "reschool-app", account: "session-cookie") {
            if let cookie = HTTPCookie(properties: [
                .name: "JSESSIONID",
                .value: value,
                .domain: "app.eschool.center",
                .path: "/",
                .version: "0"
            ]) {
                self.cookies = [cookie]
            }
        }
    }

    func logout() {

        KeychainHelper.shared.delete(service: "reschool-app", account: "session-cookie")

        KeychainHelper.shared.delete(service: "reschool-app", account: "saved-username")
        KeychainHelper.shared.delete(service: "reschool-app", account: "saved-password")

        self.cookies = []
        self.userId = nil
        self.currentPrsId = nil
        self.userProfile = nil

        Task { @MainActor in
            self.isAuthenticated = false
        }
    }

    private func logRequest(_ request: URLRequest) {
        print("\n========== API REQUEST ==========")
        print("URL: \(request.url?.absoluteString ?? "nil")")
        print("Method: \(request.httpMethod ?? "nil")")
        print("Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in

            if key.lowercased() == "cookie" {
                print("  \(key): [COOKIES HIDDEN]")
            } else {
                print("  \(key): \(value)")
            }
        }
        if let body = request.httpBody {
            if let bodyString = String(data: body, encoding: .utf8) {
                print("Body: \(bodyString)")
            } else {
                print("Body: [Binary data, \(body.count) bytes]")
            }
        } else {
            print("Body: [empty]")
        }
        print("==================================\n")
    }

    private func logResponse(_ response: URLResponse?, data: Data?, error: Error?) {
        print("\n========== API RESPONSE ==========")
        if let httpResponse = response as? HTTPURLResponse {
            print("URL: \(httpResponse.url?.absoluteString ?? "nil")")
            print("Status Code: \(httpResponse.statusCode)")
            print("Headers:")
            httpResponse.allHeaderFields.forEach { key, value in
                print("  \(key): \(value)")
            }
        } else if let response = response {
            print("Response Type: \(type(of: response))")
            print("URL: \(response.url?.absoluteString ?? "nil")")
        }

        if let error = error {
            print("Error: \(error.localizedDescription)")
        }

        if let data = data {
            print("Response Body Size: \(data.count) bytes")
            if let dataString = String(data: data, encoding: .utf8) {
                if dataString.isEmpty {
                    print("Response Body: [empty string]")
                } else {
                    print("Response Body: \(dataString)")
                }
            } else {
                print("Response Body: [Binary data, \(data.count) bytes]")
                print("Response Body (hex): \(data.map { String(format: "%02x", $0) }.joined())")
            }
        } else {
            print("Response Body: [nil]")
        }
        print("==================================\n")
    }

    private func getRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.addValue("https://app.eschool.center", forHTTPHeaderField: "Origin")
        request.addValue("https://app.eschool.center/", forHTTPHeaderField: "Referer")

        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func getDeviceModel() -> String {
        let key = "saved_device_model"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }

        var deviceList: [String] = []

        #if canImport(UIKit)
        if let asset = NSDataAsset(name: "devices") {
            if let devices = try? JSONDecoder().decode([String].self, from: asset.data) {
                deviceList = devices
            }
        }
        #endif

        if deviceList.isEmpty {
             deviceList = ["Android Device"]
        }

        let selected = deviceList.randomElement() ?? "Android Device"
        UserDefaults.standard.set(selected, forKey: key)
        return selected
    }

    func login(username: String, password: String, rememberMe: Bool = false) async throws -> Bool {
        let passwordHash = CryptoHelper.sha256(password)
        let deviceId = CryptoHelper.randomString(length: 16).lowercased()
        let pushToken = CryptoHelper.randomString(length: 152)

        let devicePayload = DevicePayload(
            cliType: "mobile", cliVer: "7.4.0", pushToken: pushToken,
            deviceId: deviceId, deviceName: "-", deviceModel: getDeviceModel(),
            cliOs: "android", cliOsVer: "9"
        )

        guard let url = URL(string: "\(baseURL)/login") else { throw URLError(.badURL) }

        let deviceJson = try JSONEncoder().encode(devicePayload)
        let deviceString = String(data: deviceJson, encoding: .utf8)!

        var request = getRequest(url: url, method: "POST")
        let bodyString = "username=\(username)&password=\(passwordHash)&device=\(deviceString)"
        request.httpBody = bodyString.data(using: .utf8)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)

            logResponse(response, data: data, error: nil)

            if let httpResponse = response as? HTTPURLResponse {

                var hasSessionCookie = false
                if let headerFields = httpResponse.allHeaderFields as? [String: String],
                   let url = response.url {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                    self.cookies.append(contentsOf: cookies)
                    hasSessionCookie = cookies.contains { $0.name == "JSESSIONID" }
                    print("DEBUG: Cookies saved: \(cookies.map { "\($0.name)=\($0.value.prefix(20))..." })")
                    print("DEBUG: Has JSESSIONID: \(hasSessionCookie)")
                }

                if httpResponse.statusCode == 200 {
                    let responseStr = String(data: data, encoding: .utf8) ?? ""

                    if responseStr.count > 5 || hasSessionCookie {
                        print("DEBUG: Login successful!")
                        self.saveSession(self.cookies)

                        if rememberMe {
                            saveCredentials(username: username, password: password)
                        } else {
                            deleteCredentials()
                        }

                        await MainActor.run { self.isAuthenticated = true }
                        try? await self.fetchState()
                        return true
                    } else {
                        print("DEBUG: Login failed - empty response and no session cookie")
                    }
                } else {
                    print("DEBUG: Login failed - status code: \(httpResponse.statusCode)")
                }
            }
            return false
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    private func saveCredentials(username: String, password: String) {
        KeychainHelper.shared.save(username, service: "reschool-app", account: "saved-username")
        KeychainHelper.shared.save(password, service: "reschool-app", account: "saved-password")
    }

    private func deleteCredentials() {
        KeychainHelper.shared.delete(service: "reschool-app", account: "saved-username")
        KeychainHelper.shared.delete(service: "reschool-app", account: "saved-password")
    }

    private func getSavedCredentials() -> (String, String)? {
        guard let username = KeychainHelper.shared.readString(service: "reschool-app", account: "saved-username"),
              let password = KeychainHelper.shared.readString(service: "reschool-app", account: "saved-password") else {
            return nil
        }
        return (username, password)
    }

    func fetchState() async throws {
        guard let url = URL(string: "\(baseURL)/state") else { return }
        let request = getRequest(url: url)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)

            if let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) {
                throw URLError(.userAuthenticationRequired)
            }

            let state = try JSONDecoder().decode(StateResponse.self, from: data)

            if state.userId == nil {
                 throw URLError(.userAuthenticationRequired)
            }

            self.userId = state.userId
            self.currentPrsId = state.user?.prsId
            self.userProfile = state.profile
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func attemptAutoLogin() async {

        if !cookies.isEmpty {
            do {
                try await fetchState()
                await MainActor.run { self.isAuthenticated = true }
                return
            } catch {
                print("Session expired: \(error)")
            }
        }

        if let (username, password) = getSavedCredentials() {
            print("Attempting re-login with saved credentials...")
            do {

                let success = try await login(username: username, password: password, rememberMe: true)
                if success {
                    return
                }
            } catch {
                print("Re-login failed: \(error)")
            }
        }

        logout()
    }
    func getThreads() async throws -> [ThreadResponse] {
        guard let url = URL(string: "\(baseURL)/chat/threads?newOnly=false&row=0&rowsCount=20") else { return [] }
        let request = getRequest(url: url)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode([ThreadResponse].self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getMessages(threadId: Int) async throws -> [MessageResponse] {

        var components = URLComponents(string: "\(baseURL)/chat/messages")!
        components.queryItems = [
            URLQueryItem(name: "getNew", value: "false"),
            URLQueryItem(name: "isSearch", value: "false"),
            URLQueryItem(name: "rowStart", value: "0"),
            URLQueryItem(name: "rowsCount", value: "25"),
            URLQueryItem(name: "threadId", value: "\(threadId)")
        ]

        var request = getRequest(url: components.url!, method: "PUT")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String?] = ["msgNums": nil, "searchText": nil]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode([MessageResponse].self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func sendMessage(threadId: Int, msgText: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/chat/sendNew") else {
            throw URLError(.badURL)
        }

        let msgUID = String(Int(Date().timeIntervalSince1970 * 1000))

        var request = getRequest(url: url, method: "POST")
        request.addValue("multipart/form-data", forHTTPHeaderField: "Content-Type")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let fields: [(String, String)] = [
            ("threadId", "\(threadId)"),
            ("msgText", msgText),
            ("msgUID", msgUID)
        ]

        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
            return [:]
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getGroupsTree() async throws -> [GroupsTreeItem] {
        var components = URLComponents(string: "\(baseURL)/groups/tree")!
        components.queryItems = [
            URLQueryItem(name: "bAllTypes", value: "false"),
            URLQueryItem(name: "bApplicants", value: "true"),
            URLQueryItem(name: "bEmployees", value: "true"),
            URLQueryItem(name: "bGroups", value: "true")
        ]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode([GroupsTreeItem].self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func searchUsers(query: String) async throws -> [UserSearchItem] {
        guard let url = URL(string: "\(baseURL)/usr/getUserListSearch") else { return [] }

        let request = getRequest(url: url)

        do {
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw URLError(.badServerResponse)
            }

            let allUsers = try JSONDecoder().decode([UserSearchItem].self, from: data)

            if query.isEmpty {
                return allUsers
            } else {
                let lowerQuery = query.localizedLowercase
                return allUsers.filter { user in
                    return (user.fio ?? "").localizedLowercase.contains(lowerQuery)
                }
            }
        } catch {
            throw error
        }
    }

    func createGroupChat(subject: String) async throws -> Int {
        guard let url = URL(string: "\(baseURL)/chat/saveThread") else { return 0 }

        var request = getRequest(url: url, method: "PUT")
        request.addValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let body: [String: Any?] = [
            "threadId": nil,
            "senderId": nil,
            "imageId": nil,
            "subject": subject,
            "isAllowReplay": 2,
            "isGroup": true,
            "interlocutor": nil
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        logRequest(request)

        let (data, response) = try await session.data(for: request)
        logResponse(response, data: data, error: nil)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        if let id = try? JSONDecoder().decode(Int.self, from: data) { return id }
        if let str = String(data: data, encoding: .utf8), let id = Int(str) { return id }
        return 0
    }

    func setGroupMembers(threadId: Int, members: [UserSearchItem]) async throws {
        guard let url = URL(string: "\(baseURL)/chat/setMembers") else { return }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        comps.queryItems = [URLQueryItem(name: "threadId", value: "\(threadId)")]

        var request = getRequest(url: comps.url!, method: "PUT")
        request.addValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let body = members.map { user in
            [
                "memberId": nil,
                "memberCode": "PRS",
                "memberObjId": user.prsId,
                "memberObjName": user.fio
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        logRequest(request)

        let (data, response) = try await session.data(for: request)
        logResponse(response, data: data, error: nil)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
    }

    func leaveChat(threadId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/chat/close_and_leave") else { return }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        comps.queryItems = [URLQueryItem(name: "threadId", value: "\(threadId)")]

        let request = getRequest(url: comps.url!)
        logRequest(request)

        let (data, response) = try await session.data(for: request)
        logResponse(response, data: data, error: nil)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
    }

    func saveThread(interlocutorId: Int) async throws -> Int {
        guard let url = URL(string: "\(baseURL)/chat/saveThread") else {
            throw URLError(.badURL)
        }

        var request = getRequest(url: url, method: "PUT")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any?] = [
            "threadId": nil,
            "senderId": nil,
            "imageId": nil,
            "subject": nil,
            "isAllowReplay": 2,
            "isGroup": false,
            "interlocutor": interlocutorId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)

            if let threadId = try? JSONDecoder().decode(Int.self, from: data) {
                return threadId
            }
            if let threadIdString = String(data: data, encoding: .utf8),
               let threadId = Int(threadIdString) {
                return threadId
            }
            throw NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить ID чата"])
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getClassByUser() async throws -> [GroupResponse] {
        if self.userId == nil {
            try await fetchState()
        }

        guard let userId = self.userId else {
            return []
        }

        var components = URLComponents(string: "\(baseURL)/usr/getClassByUser")!
        components.queryItems = [URLQueryItem(name: "userId", value: "\(userId)")]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode([GroupResponse].self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getPeriods(groupId: Int) async throws -> PeriodResponse {
        var components = URLComponents(string: "\(baseURL)/dict/periods/0")!
        components.queryItems = [URLQueryItem(name: "groupId", value: "\(groupId)")]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode(PeriodResponse.self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getDiaryUnits(periodId: Int) async throws -> [DiaryUnit] {
        if self.userId == nil {
            try await fetchState()
        }

        guard let userId = self.userId else {
            return []
        }

        var components = URLComponents(string: "\(baseURL)/student/getDiaryUnits/")!
        components.queryItems = [
            URLQueryItem(name: "userId", value: "\(userId)"),
            URLQueryItem(name: "eiId", value: "\(periodId)")
        ]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            let responseObj = try JSONDecoder().decode(DiaryUnitResponse.self, from: data)
            return responseObj.result ?? []
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getDiaryPeriod(periodId: Int) async throws -> DiaryPeriodResponse {
        if self.userId == nil {
            try await fetchState()
        }

        guard let userId = self.userId else {
            throw NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID не найден"])
        }

        var components = URLComponents(string: "\(baseURL)/student/getDiaryPeriod_/")!
        components.queryItems = [
            URLQueryItem(name: "userId", value: "\(userId)"),
            URLQueryItem(name: "eiId", value: "\(periodId)")
        ]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode(DiaryPeriodResponse.self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getPrsDiary(d1: Double, d2: Double) async throws -> PrsDiaryResponse {
        if self.currentPrsId == nil {
            try await fetchState()
        }

        guard let prsId = self.currentPrsId else {
            throw NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Prs ID не найден"])
        }

        var components = URLComponents(string: "\(baseURL)/student/getPrsDiary")!
        components.queryItems = [
            URLQueryItem(name: "prsId", value: "\(prsId)"),
            URLQueryItem(name: "d1", value: "\(Int(d1))"),
            URLQueryItem(name: "d2", value: "\(Int(d2))")
        ]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode(PrsDiaryResponse.self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getPupilUnits(prsId: Int, yearId: Int) async throws -> [PupilUnit] {
        var components = URLComponents(string: "\(baseURL)/student/getPupilUnits")!
        components.queryItems = [
            URLQueryItem(name: "prsId", value: "\(prsId)"),
            URLQueryItem(name: "yearId", value: "\(yearId)")
        ]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            let responseObj = try JSONDecoder().decode(PupilUnitsResponse.self, from: data)
            return responseObj.result ?? []
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getLPartListPupil(begDate: Double, endDate: Double, isOdod: Int, prsId: Int, yearId: Int) async throws -> [LPartTask] {
        var components = URLComponents(string: "\(baseURL)/student/getLPartListPupil")!
        components.queryItems = [
            URLQueryItem(name: "begDate", value: "\(Int(begDate))"),
            URLQueryItem(name: "endDate", value: "\(Int(endDate))"),
            URLQueryItem(name: "isOdod", value: "\(isOdod)"),
            URLQueryItem(name: "prsId", value: "\(prsId)"),
            URLQueryItem(name: "yearId", value: "\(yearId)")
        ]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode)"])
            }

            let responseObj = try JSONDecoder().decode(LPartListPupilResponse.self, from: data)
            return responseObj.result ?? []
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func getProfileNew(prsId: Int) async throws -> ProfileNewResponse {
        var components = URLComponents(string: "\(baseURL)/profile/getProfile_new")!
        components.queryItems = [URLQueryItem(name: "prsId", value: "\(prsId)")]

        let request = getRequest(url: components.url!)

        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, error: nil)
            return try JSONDecoder().decode(ProfileNewResponse.self, from: data)
        } catch {
            logResponse(nil, data: nil, error: error)
            throw error
        }
    }

    func downloadFile(endpoint: String) async throws -> URL {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let request = getRequest(url: url)

        logRequest(request)

        let (tempLocalUrl, response) = try await session.download(for: request)

        logResponse(response, data: nil, error: nil)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "File download failed: \(httpResponse.statusCode)"])
        }

        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent(response.suggestedFilename ?? "downloaded_file")

        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: tempLocalUrl, to: destinationURL)

        return destinationURL
    }

    func getImageData(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let request = getRequest(url: url)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        return data
    }
}