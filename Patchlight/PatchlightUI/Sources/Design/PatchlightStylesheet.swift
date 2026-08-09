import BroadwayCore
import BroadwayUI
import SwiftUI

/// Patchlight's trait-aware Broadway design tokens.
struct PatchlightStylesheet: BStylesheet {
    var spacing = Spacing()
    var sidebar = Sidebar()
    var emptyState = EmptyState()

    init() {}

    init(context: SlicingContext) throws {
        if context.traits.contentSizeCategory.isAccessibilitySize {
            sidebar.minimumRowHeight = 52
            emptyState.maximumWidth = 640
        }
        if context.traits.accessibility.isReduceTransparencyEnabled {
            emptyState.material = .regular
        }
    }

    static let `default` = PatchlightStylesheet()
}

extension PatchlightStylesheet {
    struct Spacing: Equatable {
        var small: CGFloat = 8
        var regular: CGFloat = 12
        var large: CGFloat = 16
        var xLarge: CGFloat = 24
        var xxLarge: CGFloat = 32
    }

    struct Sidebar: Equatable {
        #if targetEnvironment(macCatalyst)
            var dashboardWidth = Width(minimum: 210, ideal: 240, maximum: 300)
            var workspaceWidth = Width(minimum: 240, ideal: 280, maximum: 360)
            var minimumRowHeight: CGFloat = 30
        #else
            var dashboardWidth = Width(minimum: 260, ideal: 300, maximum: 360)
            var workspaceWidth = Width(minimum: 260, ideal: 330, maximum: 440)
            var minimumRowHeight: CGFloat = 44
        #endif

        struct Width: Equatable {
            var minimum: CGFloat
            var ideal: CGFloat
            var maximum: CGFloat
        }
    }

    struct EmptyState: Equatable {
        enum Material: Equatable {
            case glass
            case regular
        }

        var maximumWidth: CGFloat = 540
        var cornerRadius: CGFloat = 28
        var material = Material.glass
    }
}

private enum PatchlightThemes {
    static let current = BThemes()
}

extension View {
    public func patchlightBroadwayRoot() -> some View {
        broadwayRoot(themes: PatchlightThemes.current)
    }
}

extension EnvironmentValues {
    var patchlightStylesheet: PatchlightStylesheet {
        bContext.stylesheet(PatchlightStylesheet.self, fallback: .default)
    }
}
