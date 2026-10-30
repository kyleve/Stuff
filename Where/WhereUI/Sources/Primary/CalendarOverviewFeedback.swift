import SwiftUI

/// Rejected month activation stays actionable so touch and VoiceOver receive feedback.
struct CalendarOverviewFeedback: ViewModifier {
    let rejected: Bool
    let trigger: Int
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet.calendar.overview
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, phase in
            content
                .offset(x: style.usesSpatialMotion && rejected ? phase * style.shakeDistance : 0)
                .overlay {
                    if !style.usesSpatialMotion, rejected {
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .stroke(.secondary, lineWidth: 2)
                            .opacity(abs(phase))
                    }
                }
        } keyframes: { _ in
            LinearKeyframe(-1, duration: style.duration / 4)
            LinearKeyframe(1, duration: style.duration / 4)
            LinearKeyframe(-1, duration: style.duration / 4)
            LinearKeyframe(0, duration: style.duration / 4)
        }
    }
}
