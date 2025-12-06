import SwiftUI

struct LoginView: View {
    @StateObject private var api = APIService.shared
    @State private var username = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var animateGradient = false

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {

            LinearGradient(colors: [AppColors.primary, AppColors.secondary, Color(hex: "6DD5FA")], startPoint: animateGradient ? .topLeading : .bottomLeading, endPoint: animateGradient ? .bottomTrailing : .topTrailing)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: true)) {
                        animateGradient.toggle()
                    }
                }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 15) {
                    Image(systemName: "graduationcap.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                    Text("reSchool")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)

                    Text("Ваш электронный дневник")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.bottom, 50)

                VStack(spacing: 25) {

                    VStack(spacing: 15) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            TextField("Логин", text: $username)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        .padding()
                        .background(AppColors.card.opacity(0.9))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 2)

                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            SecureField("Пароль", text: $password)
                        }
                        .padding()
                        .background(AppColors.card.opacity(0.9))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 2)
                    }

                    Toggle("Запомнить меня", isOn: $rememberMe)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .tint(AppColors.secondary)

                    Button(action: performLogin) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 5)
                            }
                            Text(isLoading ? "Вход..." : "Войти")
                                .font(.title3.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [AppColors.primary, Color.blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        .scaleEffect(isLoading ? 0.98 : 1.0)
                    }
                    .disabled(isLoading || username.isEmpty || password.isEmpty)
                    .opacity((username.isEmpty || password.isEmpty) ? 0.6 : 1)
                }
                .padding(30)
                .background(
                    VisualEffectBlur(blurStyle: .systemThinMaterialLight)
                        .cornerRadius(25)
                        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 20)

                Spacer()

                Text("Версия \(appVersion)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 20)
            }
        }
        .alert("Ошибка входа", isPresented: $showError) {
            Button("ОК", role: .cancel) { }
        } message: {
            Text("Неверный логин или пароль. Пожалуйста, попробуйте снова.")
        }
        .task {
            isLoading = true
            await api.attemptAutoLogin()
            isLoading = false
        }
    }

    func performLogin() {
        withAnimation { isLoading = true }
        Task {
            do {
                let success = try await api.login(username: username, password: password, rememberMe: rememberMe)
                await MainActor.run {
                    withAnimation {
                        isLoading = false
                        if !success { showError = true }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        isLoading = false
                        showError = true
                    }
                }
            }
        }
    }
}

struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
