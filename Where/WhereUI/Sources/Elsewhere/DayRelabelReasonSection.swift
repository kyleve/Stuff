import SFSafeSymbols
import SwiftUI

struct DayRelabelReasonSection: View {
    let reason: DayRelabelReason

    var body: some View {
        switch reason {
            case .none:
                EmptyView()
            case let .borderDrift(region, meters):
                DayRelabelBanner(
                    icon: .locationCircle,
                    text: WhereFormat.relabelReasonBorderDrift(
                        region: region.localizedName,
                        distance: meters.map(Self.formattedDistance),
                    ),
                )
            case .travelDay:
                DayRelabelBanner(
                    icon: .arrowTriangleSwap,
                    text: String(localized: .relabelReasonTravelDay),
                )
            case let .flight(removed):
                DayRelabelBanner(
                    icon: .airplane,
                    text: WhereFormat.relabelReasonFlight(removed: removed),
                )
        }
    }

    private static func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private struct DayRelabelBanner: View {
    let icon: SFSymbol
    let text: String

    var body: some View {
        Section {
            Label {
                Text(text)
            } icon: {
                Image(systemSymbol: icon)
                    .foregroundStyle(.tint)
            }
            .font(.subheadline)
        } header: {
            Text(String(localized: .relabelReasonTitle))
        }
    }
}

#if DEBUG
    #Preview {
        DayRelabelView.snapshotPreviews
    }
#endif
