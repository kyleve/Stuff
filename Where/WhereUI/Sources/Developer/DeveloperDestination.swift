import Foundation
import SFSafeSymbols

/// One typed action exposed by the developer accordion after activation.
///
/// Most destinations become the selected HUD tool. Flyover remains a
/// full-screen cover because it owns an independent navigation domain.
enum DeveloperDestination: Hashable, Identifiable {
    case tool(DeveloperTool)
    #if DEBUG
        case flyover
    #endif

    var id: Self {
        self
    }

    var title: String {
        switch self {
            case let .tool(tool): tool.title
            #if DEBUG
                case .flyover: String(localized: .developerFlyoverLink)
            #endif
        }
    }

    var systemSymbol: SFSymbol {
        switch self {
            case let .tool(tool): tool.systemSymbol
            #if DEBUG
                case .flyover: .rectangle3Group
            #endif
        }
    }

    /// Process-independent destinations plus the always-visible logging
    /// diagnostic surface. Logs must remain reachable while their store
    /// is opening or failed; hiding the row turns those states into an
    /// undiagnosable absence.
    static var available: [Self] {
        #if DEBUG
            [
                .tool(.porthole),
                .tool(.logs),
                .tool(.openSpans),
                .flyover,
                .tool(.regionMap),
                .tool(.crashTesting),
            ]
        #else
            [.tool(.porthole)]
        #endif
    }
}
