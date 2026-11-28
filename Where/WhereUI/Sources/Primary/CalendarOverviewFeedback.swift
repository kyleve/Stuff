import BroadwayCore
import SwiftUI

/// Rejected month activation stays actionable so touch and VoiceOver receive feedback.
struct CalendarOverviewFeedback: ViewModifier {
    let rejected: Bool
    let trigger: EventTrigger
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet.calendar.overview
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, phase in
            content
                .offset(x: style.usesSpatialMotion && rejected ? phase * style.shakeDistance : 0)
                .overlay {
                    CalendarRejectionOutline(
                        visible: !style.usesSpatialMotion && rejected,
                        cornerRadius: style.cornerRadius,
                        phase: phase,
                    )
                }
        } keyframes: { _ in
            LinearKeyframe(-1, duration: style.duration / 4)
            LinearKeyframe(1, duration: style.duration / 4)
            LinearKeyframe(-1, duration: style.duration / 4)
            LinearKeyframe(0, duration: style.duration / 4)
        }
    }
}

private struct CalendarRejectionOutline: View {
    let visible: Bool
    let cornerRadius: CGFloat
    let phase: CGFloat

    var body: some View {
        if visible {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.secondary, lineWidth: 2)
                .opacity(abs(phase))
        }
    }
}

#if DEBUG
    #Preview("Unavailable month feedback") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
