import StuffCore
import SwiftUI
import WhereCore

/// A compact status line for the Settings location section: an icon + label
/// summarizing the current authorization and whether background tracking is
/// actually running.
struct LocationStatusRow: View {
    let status: LocationAuthorizationStatus
    let isTracking: Bool

    var body: some View {
        HStack(spacing: UIConstants.Spacings.large) {
            Image(systemName: presentation.symbol)
                .font(.title3)
                .foregroundStyle(presentation.tint)
                .frame(width: UIConstants.Size.statusIconWidth)
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
                title: LocalizedStrings.Settings.Status.tracking.localized,
            )
        }
        switch status {
            case .always:
                return Presentation(
                    symbol: "location.fill",
                    tint: .green,
                    title: LocalizedStrings.Settings.Status.alwaysPaused.localized,
                )
            case .whenInUse:
                return Presentation(
                    symbol: "location",
                    tint: .orange,
                    title: LocalizedStrings.Settings.Status.whenInUse.localized,
                )
            case .notDetermined:
                return Presentation(
                    symbol: "location.slash",
                    tint: .secondary,
                    title: LocalizedStrings.Settings.Status.notDetermined.localized,
                )
            case .denied:
                return Presentation(
                    symbol: "location.slash.fill",
                    tint: .red,
                    title: LocalizedStrings.Settings.Status.denied.localized,
                )
            case .restricted:
                return Presentation(
                    symbol: "lock.fill",
                    tint: .red,
                    title: LocalizedStrings.Settings.Status.restricted.localized,
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
