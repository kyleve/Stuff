import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct EditedFlightPoint: View {
    @Environment(\.stylesheet) private var stylesheet
    let point: SampleCorrectionPoint
    let model: FlightReviewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(
                point.sample.timestamp,
                format: .dateTime.hour().minute().second(),
            )
            Text(model.replacementDescription(for: point.sample.id))
                .foregroundStyle(.secondary)
            if let explanation = model
                .inferredExplanation(for: point.sample.id)
            {
                Text(explanation)
                    .font(stylesheet.flightReviewPoint.detailFont)
                    .foregroundStyle(.secondary)
            }
            if let speed = WhereFormat
                .recordedFlightSpeed(point.sample.motion?.speed)
            {
                Text(speed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let altitude = WhereFormat
                .recordedFlightAltitude(point.sample.motion?.altitude)
            {
                Text(altitude)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview { FlightDayDetailView.snapshotPreviews }
#endif
