import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case discover
    case map
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "탐색"
        case .map: "지도"
        case .saved: "저장"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkle.magnifyingglass"
        case .map: "map"
        case .saved: "bookmark"
        }
    }
}
