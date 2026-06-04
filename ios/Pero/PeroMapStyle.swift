import SwiftUI

enum PeroMapStyle {
    static let paper = Color(red: 0.969, green: 0.965, blue: 0.949)
    static let surface = Color(red: 1.000, green: 0.996, blue: 0.980)
    static let surfaceMuted = Color(red: 0.933, green: 0.933, blue: 0.914)
    static let ink = Color(red: 0.090, green: 0.102, blue: 0.114)
    static let inkSoft = Color(red: 0.204, green: 0.224, blue: 0.243)
    static let muted = Color(red: 0.545, green: 0.569, blue: 0.596)
    static let line = Color(red: 0.871, green: 0.875, blue: 0.863)
    static let accent = Color(red: 0.608, green: 0.718, blue: 0.831)
    static let accentDeep = Color(red: 0.435, green: 0.573, blue: 0.706)
    static let accentPale = Color(red: 0.863, green: 0.910, blue: 0.949)
}

extension View {
    func peroFloatingSurface(cornerRadius: CGFloat = 22) -> some View {
        background(PeroMapStyle.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PeroMapStyle.line, lineWidth: 0.7)
            }
            .shadow(color: PeroMapStyle.ink.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    func peroBottomSheetSurface() -> some View {
        background(PeroMapStyle.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .top) {
                Capsule()
                    .fill(PeroMapStyle.line)
                    .frame(width: 42, height: 4)
                    .padding(.top, 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(PeroMapStyle.line, lineWidth: 0.7)
            }
            .shadow(color: PeroMapStyle.ink.opacity(0.10), radius: 14, x: 0, y: -2)
    }
}
