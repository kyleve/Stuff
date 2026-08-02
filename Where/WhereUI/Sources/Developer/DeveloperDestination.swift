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

        /// Process-independent destinations plus the always-visible logging
        /// diagnostic surface. Logs must remain reachable while their store
        /// is opening or failed; hiding the row turns those states into an
        /// undiagnosable absence.
        static var available: [Self] {
            [
                .tool(.logs),
                .tool(.openSpans),
                .flyover,
                .tool(.regionMap),
            ]
        }
    }
#endif
