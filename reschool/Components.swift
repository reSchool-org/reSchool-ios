import SwiftUI

struct AppColors {
    static let background = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let primary = Color.blue
    static let secondary = Color.gray
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.gray.opacity(0.2), lineWidth: 1)
                )

            content
                .padding()
        }
    }
}

struct GradeBadge: View {
    let grade: Double

    var color: Color {
        if grade >= 4.5 { return AppColors.success }
        if grade >= 3.5 { return AppColors.primary }
        if grade >= 2.5 { return AppColors.warning }
        return AppColors.danger
    }

    var body: some View {
        Text(String(format: "%.2f", grade))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color)
            .clipShape(Capsule())
    }
}

struct GenericAsyncAvatar: View {
    let imageId: Int?
    let imgObjType: String?
    let imgObjId: Int?
    let fallbackText: String

    @State private var imageData: Data?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(AppColors.secondary)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(fallbackText.uppercased())
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                    )
            }
        }
        .onAppear { loadAvatar() }
    }

    private func loadAvatar() {
        guard let imageId = imageId, let imgObjType = imgObjType, let imgObjId = imgObjId else { return }

        let urlString = "https://app.eschool.center/ec-server/files/\(imgObjType)/\(imgObjId)/\(imageId)?preview=true"
        isLoading = true

        Task {
            do {
                let data = try await APIService.shared.getImageData(urlString: urlString)
                await MainActor.run {
                    self.imageData = data
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}
