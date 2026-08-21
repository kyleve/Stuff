import RegionKit
import SwiftUI
import WhereCore

/// Hosts the ranked Location cards and gives each overtake one explicit,
/// region-keyed layout interpolation.
struct LocationCardRankingStack<Content: View>: View {
    let spacing: CGFloat
    let presentation: LocationCardsPresentationModel
    let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion
    private let content: Content

    init(
        spacing: CGFloat,
        presentation: LocationCardsPresentationModel,
        motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
        @ViewBuilder content: () -> Content,
    ) {
        self.spacing = spacing
        self.presentation = presentation
        self.motion = motion
        self.content = content()
    }

    var body: some View {
        let movement = presentation.overtakeMovement
        let releasedMotion = movement?.releasedMotion ?? motion

        KeyframeAnimator(
            initialValue: CGFloat.zero,
            trigger: presentation.overtakeTrigger,
        ) { progress in
            LocationCardRankingLayout(
                spacing: spacing,
                fromOrder: movement?.fromOrder ?? [],
                toOrder: movement?.toOrder ?? [],
                progress: resolvedProgress(
                    keyframeProgress: progress,
                    movement: movement,
                ),
            ) {
                content
            }
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(
                    1,
                    duration: releasedMotion.duration,
                    spring: Spring(
                        duration: releasedMotion.duration,
                        bounce: releasedMotion.bounce,
                    ),
                )
            }
        }
    }

    /// A pending target remains at its old frames during the 500 ms gate. The
    /// trigger then owns every intermediate frame until reconciliation settles.
    func resolvedProgress(
        keyframeProgress: CGFloat,
        movement: LocationCardsPresentationModel.OvertakeMovement?,
    ) -> CGFloat {
        guard let movement else { return 1 }
        guard let motion = movement.releasedMotion, motion.usesSpatialMotion else { return 0 }
        return keyframeProgress
    }
}

#Preview {
    let presentation = LocationCardsPresentationModel(
        preferences: WherePreferences(store: InMemoryKeyValueStore()),
        year: 2026,
    )
    LocationCardRankingStack(
        spacing: 12,
        presentation: presentation,
        motion: .standard,
    ) {
        Text("California")
            .locationCardRankingRegion(.california)
        Text("New York")
            .locationCardRankingRegion(.newYork)
    }
    .padding()
}
