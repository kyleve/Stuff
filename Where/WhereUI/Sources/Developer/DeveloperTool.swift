#if DEBUG
    import Foundation
    import SFSafeSymbols

    /// A destination launched from the DEBUG-only developer overlay.
    ///
    /// Keeping the destination typed lets the overlay carry the selected tool
    /// through floating/full-screen transitions without retaining a parallel
    /// collection of labels, icons, or route flags.
    enum DeveloperTool: Hashable, Identifiable {
        case logs
        case openSpans
        case regionMap

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .logs:
                    String(localized: .developerLogsLink)
                case .openSpans:
                    String(localized: .developerOpenSpansLink)
                case .regionMap:
                    String(localized: .developerRegionMapLink)
            }
        }

        var systemSymbol: SFSymbol {
            switch self {
                case .logs: .ladybug
                case .openSpans: .timer
                case .regionMap: .map
            }
        }
    }
#endif
