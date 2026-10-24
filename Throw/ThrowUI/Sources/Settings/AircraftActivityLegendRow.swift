import SwiftUI
import ThrowCore

/// One production-shaped activity cue and its meaning.
struct AircraftActivityLegendRow: View {
    let stage: FlightActivityStage

    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.medium) {
            ZStack {
                AircraftActivityCueShape(stage: stage)
                    .stroke(
                        .primary.opacity(stylesheet.projection.activity.confirmedOpacity),
                        style: StrokeStyle(
                            lineWidth: stylesheet.projection.activity.cueLineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                        ),
                    )
                    .frame(width: 20, height: 20)
                AircraftGlyphShape(family: .airliner)
                    .fill(.primary)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 56, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                Text(stage.localizedTitle)
                Text(stage.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension FlightActivityStage {
    fileprivate var localizedTitle: LocalizedStringResource {
        switch self {
            case .inbound: .activityInboundTitle
            case .approach: .activityApproachTitle
            case .outbound: .activityOutboundTitle
            case .initialClimb: .activityInitialClimbTitle
        }
    }

    fileprivate var localizedDescription: LocalizedStringResource {
        switch self {
            case .inbound: .activityInboundDescription
            case .approach: .activityApproachDescription
            case .outbound: .activityOutboundDescription
            case .initialClimb: .activityInitialClimbDescription
        }
    }
}
