import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Current-location verification shown beneath the planned-stay date entry.
struct PlannedStayLocationStatusRow: View {
    let check: LocationForecastModel.PlannedStayLocationCheck?

    var body: some View {
        switch check?.status {
            case .checking:
                Label {
                    Text(String(localized: .locationForecastEditorLocationChecking))
                } icon: {
                    ProgressView()
                }
                .font(.subheadline)
            case .outside:
                if let check {
                    Label {
                        Text(WhereFormat.plannedStayOutsideLocation(
                            region: check.region,
                            driftThreshold: check.driftThreshold,
                        ))
                    } icon: {
                        Image(systemSymbol: .exclamationmarkTriangleFill)
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                }
            case .unavailable:
                Label(
                    String(localized: .locationForecastEditorLocationUnavailable),
                    systemSymbol: .locationSlash,
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            case .accepted, nil:
                EmptyView()
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            PlannedStayLocationStatusRow(check: .init(
                region: .newYork,
                driftThreshold: .km1,
                status: .checking,
            ))
            PlannedStayLocationStatusRow(check: .init(
                region: .newYork,
                driftThreshold: .km1,
                status: .outside,
            ))
            PlannedStayLocationStatusRow(check: .init(
                region: .newYork,
                driftThreshold: .km1,
                status: .unavailable,
            ))
        }
    }
#endif
