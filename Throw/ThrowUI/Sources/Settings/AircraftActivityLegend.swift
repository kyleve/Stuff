import SwiftUI
import ThrowCore

/// An accessible key for the projection's ambient flight-activity cues.
struct AircraftActivityLegend: View {
    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            ForEach(
                [
                    FlightActivityStage.inbound,
                    .approach,
                    .outbound,
                    .initialClimb,
                ],
                id: \.self,
            ) { stage in
                AircraftActivityLegendRow(stage: stage)
            }
        }
    }
}
