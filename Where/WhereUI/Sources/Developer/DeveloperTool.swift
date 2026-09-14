import Foundation
import SFSafeSymbols

/// A destination launched from the developer overlay.
///
/// Keeping the destination typed lets the overlay carry the selected tool
/// through floating/full-screen transitions without retaining a parallel
/// collection of labels, icons, or route flags.
enum DeveloperTool: Hashable, Identifiable {
    case porthole
    #if DEBUG
        case crashTesting
        case logs
        case openSpans
        case regionMap
    #endif

    var id: Self {
        self
    }

    var title: String {
        switch self {
            case .porthole: "Porthole"
            #if DEBUG
                case .crashTesting:
                    String(localized: .developerCrashTestingLink)
                case .logs:
                    String(localized: .developerLogsLink)
                case .openSpans:
                    String(localized: .developerOpenSpansLink)
                case .regionMap:
                    String(localized: .developerRegionMapLink)
            #endif
        }
    }

    var systemSymbol: SFSymbol {
        switch self {
            case .porthole: .ladybug
            #if DEBUG
                case .crashTesting: .exclamationmarkTriangleFill
                case .logs: .ladybug
                case .openSpans: .timer
                case .regionMap: .map
            #endif
        }
    }
}
