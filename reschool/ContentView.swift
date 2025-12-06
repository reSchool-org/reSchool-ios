import SwiftUI

struct ContentView: View {
    @StateObject private var api = APIService.shared

    var body: some View {
        if api.isAuthenticated {
            TabView {
                DiaryView()
                    .tabItem {
                        Label("Дневник", systemImage: "book.closed.fill")
                    }

                MarksView()
                    .tabItem {
                        Label("Оценки", systemImage: "chart.bar.fill")
                    }

                HomeworkView()
                    .tabItem {
                        Label("Задания", systemImage: "doc.text.fill")
                    }

                ChatsView()
                    .tabItem {
                        Label("Чаты", systemImage: "message.fill")
                    }

                ProfileView()
                    .tabItem {
                        Label("Профиль", systemImage: "person.circle.fill")
                    }

                SchoolDirectoryView()
                    .tabItem {
                        Label("Справочник", systemImage: "list.bullet.rectangle.portrait.fill")
                    }

                AboutView()
                    .tabItem {
                        Label("О приложении", systemImage: "info.circle.fill")
                    }
            }
            .accentColor(AppColors.primary)
        } else {
            LoginView()
        }
    }
}
