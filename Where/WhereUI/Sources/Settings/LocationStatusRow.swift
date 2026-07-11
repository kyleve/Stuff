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
            Image(systemName: presentation.symbol)
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
    }

    private struct Presentation {
        let symbol: String
        let tint: Color
        let title: String
    }

    private var presentation: Presentation {
        // Active tracking trumps the raw status: it's the happy path.
        if isTracking {
            return Presentation(
                symbol: "location.fill",
                tint: .green,
                title: Strings.settingsStatusTracking,
            )
        }
        switch status {
            case .always:
                return Presentation(
                    symbol: "location.fill",
                    tint: .green,
                    title: Strings.settingsStatusAlwaysPaused,
                )
            case .whenInUse:
                return Presentation(
                    symbol: "location",
                    tint: .orange,
                    title: Strings.settingsStatusWhenInUse,
                )
            case .notDetermined:
                return Presentation(
                    symbol: "location.slash",
                    tint: .secondary,
                    title: Strings.settingsStatusNotDetermined,
                )
            case .denied:
                return Presentation(
                    symbol: "location.slash.fill",
                    tint: .red,
                    title: Strings.settingsStatusDenied,
                )
            case .restricted:
                return Presentation(
                    symbol: "lock.fill",
                    tint: .red,
                    title: Strings.settingsStatusRestricted,
                )
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
