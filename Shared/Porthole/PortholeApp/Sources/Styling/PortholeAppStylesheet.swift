import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI

/// The Porthole app's design tokens, as a Broadway ``BStylesheet``. Small for
/// now — mostly spacing — seeded at the app root by ``portholeAppBroadwayRoot()``.
struct PortholeAppStylesheet: BStylesheet {
    var spacing = Spacing()
    var monospacedBody: Font = .system(.body, design: .monospaced)

    init() {}
    init(context _: SlicingContext) throws {}

    static let `default` = PortholeAppStylesheet()

    struct Spacing: Equatable {
        var small: CGFloat = 8
        var medium: CGFloat = 16
        var large: CGFloat = 24
    }
}

extension View {
    func portholeAppBroadwayRoot() -> some View {
        broadwayRoot(themes: BThemes())
    }
}

extension EnvironmentValues {
    var appStylesheet: PortholeAppStylesheet {
        bContext.stylesheet(PortholeAppStylesheet.self, fallback: .default)
    }
}
