import SwiftUI

struct PlaceholderDetailScreen: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle(title)
    }
}

#Preview {
    NavigationStack {
        PlaceholderDetailScreen(title: "조용한 산책", message: "상세 화면 예시입니다.")
    }
}
