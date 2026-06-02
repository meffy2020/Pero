import SwiftUI

struct MapScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("지도 탐색")
                .font(.title2.weight(.semibold))
            Text("테마를 선택하면 지도와 장소 카드가 함께 갱신되는 모바일 탐색 화면입니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        MapScreen()
    }
}
