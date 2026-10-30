import Foundation

extension ViewAnimationDescriptor {
    /// Finite playback stops requesting frames after its last complete cycle.
    public func isComplete(at elapsed: Double) -> Bool {
        switch repetition {
            case .once: elapsed >= delay + duration
            case let .count(count, autoreverses):
                elapsed >= delay + duration * Double(count) * (autoreverses ? 2 : 1)
            case .forever: false
        }
    }

    /// Samples elapsed seconds without wall-clock dependencies or retained animation tasks.
    public func pose(at elapsed: Double) -> Pose {
        guard elapsed >= delay else { return from }
        let time = max(0, elapsed - delay) / duration
        let reverses: Bool
        let cycles: Double
        switch repetition {
            case .once: reverses = false; cycles = 1
            case let .count(count, autoreverses): reverses = autoreverses; cycles = Double(count)
            case let .forever(autoreverses): reverses = autoreverses; cycles = .infinity
        }
        let legs = reverses ? 2.0 : 1.0
        let progress: Double
        if time >= cycles * legs {
            progress = reverses ? 0 : 1
        } else {
            let leg = floor(time)
            let fraction = time - leg
            progress = reverses && leg
                .truncatingRemainder(dividingBy: 2) == 1 ? 1 - fraction : fraction
        }
        let eased: Double = switch curve {
            case .linear: progress
            case .easeIn: progress * progress
            case .easeOut: 1 - (1 - progress) * (1 - progress)
            case .easeInOut: (1 - cos(.pi * progress)) / 2
        }
        func mix(_ start: Double, _ end: Double) -> Double {
            start + (end - start) * eased
        }
        return Pose(
            opacity: mix(from.opacity, to.opacity),
            offsetX: mix(from.offsetX, to.offsetX),
            offsetY: mix(from.offsetY, to.offsetY),
            scaleX: mix(from.scaleX, to.scaleX),
            scaleY: mix(from.scaleY, to.scaleY),
            rotation: mix(from.rotation, to.rotation),
        )
    }
}
