import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// The information shared by actionable and informational GPS point rows.
struct FlightReviewPointContent: View {
    let point: FlightReviewPresentation.Point
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading) {
            Text(point.point.sample.timestamp, format: .dateTime.hour().minute().second())
                .font(stylesheet.flightReviewPoint.titleFont)
            Text(point.point.regions.isEmpty
                ? String(localized: .flightReviewPointExcluded)
                : point.point.regions.map(\.localizedName).sorted().joined(separator: ", "))
            RecordedPointsMap(data: point.map, variant: .pointPreview)
                .clipShape(RoundedRectangle(cornerRadius: stylesheet.flightReviewPoint
                        .mapCornerRadius))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Text(WhereFormat.recordedFlightCoordinate(point.point.sample.coordinate))
                .font(stylesheet.flightReviewPoint.detailFont)
                .foregroundStyle(.secondary)
            Text(point.evidence.explanation)
                .font(stylesheet.flightReviewPoint.detailFont)
                .foregroundStyle(.secondary)
            if let speed = WhereFormat.recordedFlightSpeed(point.point.sample.motion?.speed) {
                Text(speed)
                    .font(stylesheet.flightReviewPoint.detailFont)
                    .foregroundStyle(.secondary)
            }
            if let correction = point.correction {
                Text(correction.action.title)
                    .foregroundStyle(.tint)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: stylesheet.flightReviewPoint.minimumActionHeight,
                        alignment: .leading,
                    )
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#if DEBUG
    #Preview {
        FlightReviewPointRow.snapshotPreviews
    }
#endif
