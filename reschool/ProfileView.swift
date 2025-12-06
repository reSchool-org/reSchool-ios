import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    private let api = APIService.shared

    @Published var state: StateResponse?
    @Published var extendedProfile: ProfileNewResponse?
    @Published var isLoading = false
    @Published var error: String?

    func loadProfile() async {
        isLoading = true
        error = nil

        do {

            try await api.fetchState()

            if let prsId = api.currentPrsId {
                self.extendedProfile = try await api.getProfileNew(prsId: prsId)
            }

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

struct ProfileView: View {
    @StateObject private var api = APIService.shared
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                } else if let error = viewModel.error {
                    VStack {
                        Text(error).foregroundColor(.red)
                        Button("Повторить") { Task { await viewModel.loadProfile() } }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {

                            VStack {
                                Circle()
                                    .fill(AppColors.primary)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Text(getInitials())
                                            .font(.system(size: 40, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                    .shadow(radius: 5)

                                Text(getFullName())
                                    .font(.title2)
                                    .bold()

                                Text(viewModel.extendedProfile?.login ?? "User")
                                    .foregroundColor(.gray)
                            }
                            .padding(.top)

                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    InfoRow(icon: "person.text.rectangle", title: "ID", value: "\(api.userId ?? 0)")
                                    if let birthDate = viewModel.extendedProfile?.birthDate {
                                        InfoRow(icon: "calendar", title: "Дата рождения", value: birthDate)
                                    }
                                    if let phone = api.userProfile?.phoneMob {
                                        InfoRow(icon: "phone", title: "Телефон", value: phone)
                                    }
                                    if let data = viewModel.extendedProfile?.data {
                                        let genderStr = (data.gender == 1) ? "Мужской" : "Женский"
                                        InfoRow(icon: "person.fill.questionmark", title: "Пол", value: genderStr)
                                    }
                                }
                            }
                            .padding(.horizontal)

                            if let relations = viewModel.extendedProfile?.prsRel, !relations.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("Семья")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ForEach(relations.indices, id: \.self) { idx in
                                        let rel = relations[idx]
                                        GlassCard {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(rel.relName ?? "Родственник")
                                                    .font(.headline)
                                                    .foregroundColor(AppColors.primary)

                                                if let data = rel.data {
                                                    let fio = [data.lastName, data.firstName, data.middleName]
                                                        .compactMap { $0 }
                                                        .joined(separator: " ")

                                                    if !fio.isEmpty {
                                                        Text(fio).bold()
                                                    }

                                                    if let phone = data.mobilePhone ?? data.homePhone {
                                                        Label(phone, systemImage: "phone")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }

                                                    if let email = data.email {
                                                        Label(email, systemImage: "envelope")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }

                            if let pupils = viewModel.extendedProfile?.pupil, !pupils.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("Обучение")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ForEach(pupils, id: \.yearId) { pupil in
                                        GlassCard {
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    Text(pupil.eduYear ?? "")
                                                        .font(.headline)
                                                    Text(pupil.className ?? "")
                                                        .foregroundColor(.gray)
                                                }
                                                Spacer()
                                                if (pupil.isReady ?? 0) == 1 {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }

                            Button(action: {
                                api.logout()
                            }) {
                                Text("Выйти")
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.card)
                                    .cornerRadius(12)
                                    .shadow(radius: 2)
                            }
                            .padding()
                        }
                        .padding(.bottom)
                    }
                }
            }
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await viewModel.loadProfile()
        }
    }

    func getFullName() -> String {
        if let fio = viewModel.extendedProfile?.fio { return fio }
        return api.userProfile?.fullName ?? "Загрузка..."
    }

    func getInitials() -> String {
        let name = getFullName()
        let components = name.components(separatedBy: " ")
        if let first = components.first?.prefix(1), let last = components.last?.prefix(1) {
            return "\(first)\(last)"
        }
        return "?"
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppColors.primary)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textPrimary)
        }
    }
}
