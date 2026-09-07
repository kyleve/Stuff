import SFSafeSymbols
import SwiftUI
import WhereCore

/// A compact status line for the Settings location section: an icon + label
/// summarizing the current authorization and whether background tracking is
/// actually running.
struct LocationStatusRow: View {
    let status: LocationAuthorizationStatus
    let isTracking: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemSymbol: presentation.symbol)
                .font(.title3)
                .foregroundStyle(presentation.tint)
                .frame(width: stylesheet.size.statusIconWidth)
                .accessibilityHidden(true)

            Text(presentation.title)
                .font(.subheadline)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.title)
        // Log View Mode: reveal an inspect badge that opens the session's
        // location/authorization events. A no-op in release.
        .debugLogInspectable(WhereLog.session)
    }

    private struct Presentation {
        let symbol: SFSymbol
        let tint: Color
        let title: String
    }

    private var presentation: Presentation {
        // Active tracking trumps the raw status: it's the happy path.
        let title = Self.statusTitle(status: status, isTracking: isTracking)
        if isTracking {
            return Presentation(symbol: .locationFill, tint: .green, title: title)
        }
        switch status {
            case .always:
                return Presentation(symbol: .locationFill, tint: .green, title: title)
            case .whenInUse:
                return Presentation(symbol: .location, tint: .orange, title: title)
            case .notDetermined:
                return Presentation(symbol: .locationSlash, tint: .secondary, title: title)
            case .denied:
                return Presentation(symbol: .locationSlashFill, tint: .red, title: title)
            case .restricted:
                return Presentation(symbol: .lockFill, tint: .red, title: title)
        }
    }

    /// The status line's title, shared with the Settings location row subtitle so
    /// the drill-in row summarizes the same state the screen shows.
    static func statusTitle(status: LocationAuthorizationStatus, isTracking: Bool) -> String {
        if isTracking { return String(localized: .settingsStatusTracking) }
        switch status {
            case .always: return String(localized: .settingsStatusAlwaysPaused)
            case .whenInUse: return String(localized: .settingsStatusWhenInUse)
            case .notDetermined: return String(localized: .settingsStatusNotDetermined)
            case .denied: return String(localized: .settingsStatusDenied)
            case .restricted: return String(localized: .settingsStatusRestricted)
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            Section {
                LocationStatusRow(status: .always, isTracking: true)
                LocationStatusRow(status: .always, isTracking: false)
                LocationStatusRow(status: .whenInUse, isTracking: false)
                LocationStatusRow(status: .notDetermined, isTracking: false)
                LocationStatusRow(status: .denied, isTracking: false)
                LocationStatusRow(status: .restricted, isTracking: false)
            }
        }
    }
#endif
