import SwiftUI
import ViewDocumentCore

/// Visibility owns playback. Finite animations stop the timeline at their final pose.
struct ViewDocumentAnimatedView: View {
    let animation: ViewAnimationDescriptor
    let policy: ViewDocumentView.Policy
    let content: AnyView
    @State private var playback = Playback.waiting

    private enum Playback {
        case waiting
        case running(since: Date)
        case holding(ViewAnimationDescriptor.Pose)

        var isPaused: Bool {
            switch self {
                case .waiting, .holding: true
                case .running: false
            }
        }
    }

    var body: some View {
        if policy.motionIsStatic || !policy.isActive {
            posed(animation.staticPose)
        } else {
            TimelineView(.animation(
                minimumInterval: 1 / 30,
                paused: playback.isPaused,
            )) { context in
                let elapsed: Double = if case let .running(epoch) = playback {
                    context.date.timeIntervalSince(epoch)
                } else { 0 }
                let pose: ViewAnimationDescriptor.Pose = switch playback {
                    case .waiting: animation.from
                    case .running: animation.pose(at: elapsed)
                    case let .holding(value): value
                }
                posed(pose)
                    .onChange(of: animation.isComplete(at: elapsed)) { _, complete in
                        if complete { playback = .holding(pose) }
                    }
            }
            .onAppear { playback = .running(since: Date()) }
            .onDisappear { playback = .waiting }
        }
    }

    private func posed(_ pose: ViewAnimationDescriptor.Pose) -> some View {
        content
            .opacity(pose.opacity)
            .scaleEffect(x: pose.scaleX, y: pose.scaleY)
            .rotationEffect(.degrees(pose.rotation))
            .offset(x: pose.offsetX, y: pose.offsetY)
    }
}
