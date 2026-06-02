import SwiftUI

struct SavedPlacesScreen: View {
    var body: some View {
        ContentUnavailableView(
            "저장한 장소 없음",
            systemImage: "bookmark",
            description: Text("마음에 드는 장소를 저장하면 이곳에서 다시 확인할 수 있습니다.")
        )
    }
}

#Preview {
    NavigationStack {
        SavedPlacesScreen()
    }
}
