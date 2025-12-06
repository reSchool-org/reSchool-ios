import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    @AppStorage("displayOnlyCurrentClass") var displayOnlyCurrentClass: Bool = false

    @AppStorage("hwDaysPast") var hwDaysPast: Int = 14
    @AppStorage("hwDaysFuture") var hwDaysFuture: Int = 60
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section(header: Text("Дневник и Оценки")) {
                Toggle("Только текущий класс", isOn: $settings.displayOnlyCurrentClass)
                Text("Если включено, будут отображаться данные только за текущий учебный год.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Section(header: Text("Период загрузки ДЗ (дней)")) {
                HStack {
                    Text("Прошлое:")
                    TextField("14", value: $settings.hwDaysPast, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                    Stepper("", value: $settings.hwDaysPast, in: 1...365)
                        .labelsHidden()
                }

                HStack {
                    Text("Будущее:")
                    TextField("60", value: $settings.hwDaysFuture, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                    Stepper("", value: $settings.hwDaysFuture, in: 0...365)
                        .labelsHidden()
                }

                Text("Настройка диапазона отображения домашних заданий относительно текущей даты.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Section(header: Text("О приложении")) {
                HStack {
                    Text("Версия")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Настройки")
    }
}
