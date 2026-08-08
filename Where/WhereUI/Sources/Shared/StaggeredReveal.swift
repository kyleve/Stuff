import SwiftUI

extension EnvironmentValues {
    @Entry fileprivate var staggeredRevealIsRevealed = true
    @Entry fileprivate var staggeredRevealMotionIsStatic = true
}

/// Coordinates a one-shot, ordered entrance for child panes. Reduce Motion and
/// snapshot capture both render the final state immediately through
/// ``MotionIsStatic``.
struct StaggeredRevealScope<Content: View>: View {
    private let content: Content

    @State private var hasRevealed = false
    @MotionIsStatic private var motionIsStatic

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.staggeredRevealIsRevealed, motionIsStatic || hasRevealed)
            .environment(\.staggeredRevealMotionIsStatic, motionIsStatic)
            .task {
                guard !hasRevealed else { return }
                guard !motionIsStatic else {
                    hasRevealed = true
                    return
                }
                await Task.yield()
                guard !Task.isCancelled else { return }
                hasRevealed = true
            }
    }
}

extension View {
    /// Reveals this pane at its ordered point within the nearest
    /// ``StaggeredRevealScope``. Outside a scope, content stays fully visible.
    func staggeredReveal(order: Int) -> some View {
        modifier(StaggeredRevealModifier(order: order))
    }
}

private struct StaggeredRevealModifier: ViewModifier {
    let order: Int

    @Environment(\.staggeredRevealIsRevealed) private var isRevealed
    @Environment(\.staggeredRevealMotionIsStatic) private var motionIsStatic
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let presentation = stylesheet.motion.staggeredReveal.presentation(
            isRevealed: isRevealed,
            motionIsStatic: motionIsStatic,
            order: order,
        )
        content
            .opacity(presentation.opacity)
            .offset(y: presentation.verticalOffset)
            .animation(presentation.animation, value: isRevealed)
    }
}
