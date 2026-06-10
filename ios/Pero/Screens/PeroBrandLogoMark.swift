import SwiftUI

struct PeroBrandLogoMark: View {
    let size: CGFloat

    var body: some View {
        Image("pero-brand-logo")
            .resizable()
            .scaledToFit()
            .padding(size * 0.12)
            .frame(width: size, height: size)
            .background(PeroMapStyle.surface, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(PeroMapStyle.line.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: PeroMapStyle.ink.opacity(0.08), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}
