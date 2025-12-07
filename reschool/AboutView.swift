import SwiftUI

struct AboutView: View {
    @AppStorage("saved_device_model") private var deviceModel: String = "Неизвестно"

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .cornerRadius(12)

                            VStack(alignment: .leading) {
                                Text("reSchool")
                                    .font(.title2)
                                    .bold()
                                Text("Версия \(appVersion)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 5)

                        Text("Это проект с открытым исходным кодом, который не аффилирован с официальными разработчиками \"eSchool\".")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Устройство")) {
                    HStack {
                        Text("Отправка авторизации")
                        Spacer()
                        Text(deviceModel)
                            .foregroundColor(.gray)
                    }
                    Button(action: {
                        _ = APIService.shared.randomizeDeviceModel()
                    }) {
                        Text("Сменить устройство")
                            .foregroundColor(.blue)
                    }
                }

                Section(header: Text("Ссылки")) {
                    Link(destination: URL(string: "https://github.com/reSchool-org")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("О приложении")
        }
        .navigationViewStyle(.stack)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
