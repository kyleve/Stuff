#if DEBUG
    import Foundation

    /// One typed action exposed by the DEBUG-only developer accordion.
    ///
    /// Most destinations become the selected HUD tool. Flyover remains a
    /// full-screen cover because it owns an independent navigation domain.
    enum DeveloperDestination: Hashable, Identifiable {
        case tool(DeveloperTool)
        case flyover

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case let .tool(tool): tool.title
                case .flyover: String(localized: .developerFlyoverLink)
            }
        }

        var systemImage: String {
            switch self {
                case let .tool(tool): tool.systemImage
                case .flyover: "rectangle.3.group"
            }
        }

        static func available(hasLogStore: Bool, hasInspector: Bool) -> [Self] {
            [
                hasLogStore ? .tool(.logs) : nil,
                .tool(.openSpans),
                hasInspector ? .tool(.swiftDataInspector) : nil,
                .flyover,
                .tool(.regionMap),
            ].compactMap(\.self)
        }
    }
#endif
