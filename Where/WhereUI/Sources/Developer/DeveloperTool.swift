#if DEBUG
    import Foundation

    /// A destination launched from the DEBUG-only developer overlay.
    ///
    /// Keeping the destination typed lets the overlay carry the selected tool
    /// through floating/full-screen transitions without retaining a parallel
    /// collection of labels, icons, or route flags.
    enum DeveloperTool: CaseIterable, Equatable, Identifiable {
        case logs
        case openSpans
        case swiftDataInspector
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
                case .swiftDataInspector:
                    String(localized: .developerInspectorLink)
                case .regionMap:
                    String(localized: .developerRegionMapLink)
            }
        }

        var systemImage: String {
            switch self {
                case .logs: "ladybug"
                case .openSpans: "timer"
                case .swiftDataInspector: "cylinder.split.1x2"
                case .regionMap: "map"
            }
        }

        static func available(hasLogStore: Bool, hasInspector: Bool) -> [Self] {
            allCases.filter { tool in
                switch tool {
                    case .logs: hasLogStore
                    case .swiftDataInspector: hasInspector
                    case .openSpans, .regionMap: true
                }
            }
        }
    }
#endif
