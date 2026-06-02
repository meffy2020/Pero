import SwiftUI

struct SavedPlacesScreen: View {
    @State private var showsSampleSavedPlace = false

    var body: some View {
        List {
            Section {
                Toggle("저장 예시 보기", isOn: $showsSampleSavedPlace.animation())
            }

            if showsSampleSavedPlace {
                Section("저장한 장소") {
                    NavigationLink(value: AppRoute.place("서울숲")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("서울숲")
                                .font(.headline)
                            Text("조용한 산책 테마에서 저장됨")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Section {
                    StateMessageView(
                        icon: "bookmark",
                        title: "저장한 장소 없음",
                        message: "마음에 드는 장소를 저장하면 이곳에서 다시 확인할 수 있습니다."
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SavedPlacesScreen()
    }
}
