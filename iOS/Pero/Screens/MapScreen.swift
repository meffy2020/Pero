import SwiftUI

struct MapScreen: View {
    private let mapNotes = [
        "테마를 선택하면 지도와 장소 카드가 함께 갱신됩니다.",
        "카드를 누르면 지도 초점과 상세 설명이 같은 장소로 맞춰집니다.",
        "실제 지도 SDK 연결 전까지는 모바일 흐름을 검증하는 자리표시자입니다."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mapPlaceholder
                VStack(alignment: .leading, spacing: 12) {
                    Text("지도 화면 상태")
                        .font(.headline)
                    ForEach(mapNotes, id: \.self) { note in
                        Label(note, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
    }

    private var mapPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.gray.opacity(0.12))
                .frame(minHeight: 320)
            VStack(spacing: 14) {
                Image(systemName: "map")
                    .font(.system(size: 58))
                    .foregroundStyle(.secondary)
                Text("지도 탐색 준비됨")
                    .font(.title2.weight(.semibold))
                Text("장소 좌표와 추천 이유를 연결할 네이티브 지도 영역입니다.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("지도 탐색 준비됨")
    }
}

#Preview {
    NavigationStack {
        MapScreen()
    }
}
