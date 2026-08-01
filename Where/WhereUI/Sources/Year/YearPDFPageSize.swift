import CoreGraphics
import Foundation

/// Paper size for the annual report's portrait body. The raw-GPS appendix
/// swaps these dimensions to landscape without changing the selected paper.
enum YearPDFPageSize: String, CaseIterable, Hashable, Identifiable {
    case letter
    case a4

    var id: Self {
        self
    }

    var portraitBounds: CGRect {
        switch self {
            case .letter:
                CGRect(x: 0, y: 0, width: 612, height: 792)
            case .a4:
                CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        }
    }

    var landscapeBounds: CGRect {
        let portrait = portraitBounds
        return CGRect(x: 0, y: 0, width: portrait.height, height: portrait.width)
    }

    static func defaultValue(for locale: Locale) -> Self {
        switch locale.region?.identifier {
            case "US", "CA": .letter
            case .none, .some: .a4
        }
    }
}
