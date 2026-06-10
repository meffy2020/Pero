import SwiftUI
import UIKit

struct PeroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PeroMapStyle.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .padding(.horizontal, 10)
            .background(
                configuration.isPressed ? PeroMapStyle.surfaceMuted : PeroMapStyle.surface,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(PeroMapStyle.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct KakaoDirectionsButton: View {
    let card: RecommendationCardModel

    var body: some View {
        Button(action: openDirections) {
            Label("길찾기", systemImage: "arrow.triangle.turn.up.right.circle")
                .frame(maxWidth: .infinity)
        }
    }

    private func openDirections() {
        if
            let appURL = card.kakaoMapDirectionsAppURL,
            UIApplication.shared.canOpenURL(appURL)
        {
            UIApplication.shared.open(appURL)
            return
        }
        UIApplication.shared.open(card.kakaoMapDirectionsWebURL)
    }
}
