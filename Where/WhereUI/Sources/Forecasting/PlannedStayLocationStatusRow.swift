import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Current-location verification shown beneath the planned-stay date entry.
struct PlannedStayLocationStatusRow: View {
    let check: LocationForecastModel.PlannedStayLocationCheck?

    @Environment(\.stylesheet) private var stylesheet

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
                    let style = stylesheet.plannedStayWarningStamp
                    StampBanner(
                        systemSymbol: .exclamationmarkTriangleFill,
                        style: style,
                        showsAccessory: false,
                    ) {
                        Text(WhereFormat.plannedStayOutsideLocation(
                            region: check.region,
                            driftThreshold: check.driftThreshold,
                        ))
                        .font(style.detailFont)
                        .foregroundStyle(.primary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
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
