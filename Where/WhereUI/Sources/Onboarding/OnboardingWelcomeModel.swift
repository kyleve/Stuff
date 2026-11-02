import Foundation
import Observation

/// Holds the completion cover until the destination is ready and visibly presented.
/// An interrupted hold or reveal starts a fresh visible hold on return.
@MainActor
@Observable
final class OnboardingWelcomeModel {
    enum Phase: Equatable {
        case inactive
        case waiting
        case holding(until: ContinuousClock.Instant)
        case revealing(deadline: ContinuousClock.Instant)
    }

    private(set) var phase = Phase.inactive

    var isPresented: Bool {
        phase != .inactive
    }

    var coversContent: Bool {
        switch phase {
            case .waiting, .holding: true
            case .inactive, .revealing: false
        }
    }

    func present() {
        guard phase == .inactive else { return }
        phase = .waiting
    }

    func startHold(at instant: ContinuousClock.Instant, duration: Duration) -> ContinuousClock
        .Instant?
    {
        switch phase {
            case .waiting:
                let deadline = instant.advanced(by: duration)
                phase = .holding(until: deadline)
                return deadline
            case let .holding(deadline):
                return deadline
            case .inactive, .revealing:
                return nil
        }
    }

    func beginReveal(
        at instant: ContinuousClock.Instant,
        deadline: ContinuousClock.Instant,
    ) -> Bool {
        guard phase == .holding(until: deadline), instant >= deadline else { return false }
        phase = .revealing(deadline: deadline)
        return true
    }

    func finishReveal(deadline: ContinuousClock.Instant) -> Bool {
        guard phase == .revealing(deadline: deadline) else { return false }
        phase = .inactive
        return true
    }

    func pause() {
        switch phase {
            case .holding, .revealing: phase = .waiting
            case .inactive, .waiting: break
        }
    }

    func cancel() {
        guard phase != .inactive else { return }
        phase = .inactive
    }
}
