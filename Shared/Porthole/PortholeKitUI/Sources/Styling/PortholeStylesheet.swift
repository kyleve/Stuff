import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI

/// PortholeKitUI's design tokens, resolved as a Broadway ``BStylesheet``. Most
/// tokens are fixed; a slice derives from the ``BContext`` traits (a roomier
/// pairing-code face at accessibility Dynamic Type sizes). Views read the active
/// tokens via `@Environment(\.stylesheet)` (seeded by
/// ``SwiftUI/View/portholeBroadwayRoot()``); off the `View` tree, use ``default``.
struct PortholeStylesheet: BStylesheet {
    var spacing = Spacing()
    var code = CodeStyle.standard
    var palette = Palette.standard
    var typography = Typography.standard

    init() {}

    init(context: SlicingContext) throws {
        // Start from the fixed set, then adjust only the trait-reactive slice so
        // a default/system context reproduces `default`.
        if context.traits.contentSizeCategory.isAccessibilitySize {
            code.digitTracking = 10
        }
    }

    /// The fixed token set: the fallback off the `View` tree and when no Broadway
    /// root has seeded a context.
    static let `default` = PortholeStylesheet()
}

extension PortholeStylesheet {
    /// Generic spacing scale in points.
    struct Spacing: Equatable {
        var small: CGFloat = 8
        var medium: CGFloat = 16
        var large: CGFloat = 24
    }

    /// The large pairing-code display.
    struct CodeStyle: Equatable {
        var font: Font = .system(size: 44, weight: .bold, design: .monospaced)
        /// Extra tracking between digits.
        var digitTracking: CGFloat = 6
        var verticalPadding: CGFloat = 12

        static let standard = CodeStyle()
    }

    /// Semantic colors for status.
    struct Palette: Equatable {
        var advertising: Color = .green
        var idle: Color = .secondary
        var sessionBadge: Color = .blue

        static let standard = Palette()
    }

    /// Display faces named by role.
    struct Typography: Equatable {
        var title: Font = .headline
        var body: Font = .body
        var caption: Font = .caption
        var hostName: Font = .body.weight(.medium)
        var hostDetail: Font = .caption

        static let standard = Typography()
    }
}

/// PortholeKitUI's Broadway themes, seeded at each root by
/// ``SwiftUI/View/portholeBroadwayRoot()``. Empty for now — the sheet derives
/// from traits, not themes.
enum PortholeThemes {
    static var current: BThemes {
        BThemes()
    }
}

extension View {
    /// Seeds PortholeKitUI's Broadway context (live system traits plus
    /// ``PortholeThemes``) so descendants resolve `@Environment(\.stylesheet)`
    /// against real traits rather than ``PortholeStylesheet/default``. Applied on
    /// each public view so it styles correctly with or without a host app root.
    func portholeBroadwayRoot() -> some View {
        broadwayRoot(themes: PortholeThemes.current)
    }
}

extension EnvironmentValues {
    /// The active PortholeKitUI tokens, resolved from the Broadway `BContext`
    /// seeded by ``SwiftUI/View/portholeBroadwayRoot()``; falls back to
    /// ``PortholeStylesheet/default`` with no root present.
    var stylesheet: PortholeStylesheet {
        bContext.stylesheet(PortholeStylesheet.self, fallback: .default)
    }
}
