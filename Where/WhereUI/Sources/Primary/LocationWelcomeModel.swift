import Foundation
import Observation
import RegionKit
import WhereCore

/// App-wide acquisition and presentation state for the live-region welcome.
@MainActor
@Observable
public final class LocationWelcomeModel {
    public struct Presentation: Equatable {
        public enum Greeting: Equatable {
            case first
            case returnVisit
        }

        public let region: Region
        public let greeting: Greeting
    }

    enum ActionRequired: Equatable {
        case locationAccess
        case preciseLocation
    }

    enum State: Equatable {
        case idle
        case locating(showsProgress: Bool)
        case actionRequired(ActionRequired)
        case presenting(Presentation)
    }

    enum Accessory: Equatable {
        case locating
        case actionRequired(ActionRequired)
    }

    private enum ResolutionEvent {
        case delayElapsed
        case delayCancelled
        case resolved(CurrentRegionResolution)
    }

    private(set) var state: State = .idle

    var presentation: Presentation? {
        guard case let .presenting(presentation) = state else { return nil }
        return presentation
    }

    var accessory: Accessory? {
        switch state {
            case .locating(showsProgress: true): .locating
            case let .actionRequired(action): .actionRequired(action)
            case .idle, .locating(showsProgress: false), .presenting: nil
        }
    }

    private let resolver: CurrentRegionResolver
    private let preferences: WherePreferences
    private let now: @Sendable () -> Date
    private let findingDelay: Duration
    private var resolutionSequence: UInt64 = 0

    init(
        services: WhereServices,
        preferences: WherePreferences,
        now: @escaping @Sendable () -> Date,
        findingDelay: Duration = .seconds(1),
    ) {
        resolver = services.currentRegion
        self.preferences = preferences
        self.now = now
        self.findingDelay = findingDelay
    }

    /// Performs one independent foreground lookup. A later lookup supersedes
    /// any earlier result that reaches the model out of order.
    func resolve() async {
        guard preferences.showsLocationWelcome else { return }
        let (sequence, overflow) = resolutionSequence.addingReportingOverflow(1)
        precondition(!overflow, "Location welcome resolution sequence exhausted UInt64.")
        resolutionSequence = sequence
        state = .locating(showsProgress: false)

        let resolution = await withTaskGroup(
            of: ResolutionEvent.self,
            returning: CurrentRegionResolution.self,
        ) { group in
            let resolver = resolver
            let now = now
            group.addTask {
                await .resolved(resolver.resolve(now: now()))
            }
            group.addTask { [findingDelay] in
                do {
                    try await Task.sleep(for: findingDelay)
                    return .delayElapsed
                } catch {
                    return .delayCancelled
                }
            }

            for await event in group {
                switch event {
                    case .delayElapsed:
                        guard
                            !Task.isCancelled,
                            sequence == resolutionSequence,
                            state == .locating(showsProgress: false)
                        else { continue }
                        state = .locating(showsProgress: true)
                    case .delayCancelled:
                        continue
                    case let .resolved(resolution):
                        group.cancelAll()
                        return resolution
                }
            }
            return .unavailable(.location(.cancellation))
        }

        guard
            !Task.isCancelled,
            preferences.showsLocationWelcome,
            sequence == resolutionSequence
        else {
            if sequence == resolutionSequence { state = .idle }
            return
        }

        switch resolution {
            case let .resolved(region):
                let previous = preferences.lastWelcomedRegion
                guard region != previous else {
                    state = .idle
                    return
                }
                state = .presenting(Presentation(
                    region: region,
                    greeting: previous == nil ? .first : .returnVisit,
                ))
            case let .unavailable(reason):
                state = actionRequired(for: reason).map(State.actionRequired) ?? .idle
        }
    }

    func dismiss() {
        guard let presentation else { return }
        preferences.lastWelcomedRegion = presentation.region
        state = .idle
    }

    func resetIfDisabled() {
        guard preferences.showsLocationWelcome == false else { return }
        let (sequence, overflow) = resolutionSequence.addingReportingOverflow(1)
        precondition(!overflow, "Location welcome resolution sequence exhausted UInt64.")
        resolutionSequence = sequence
        state = .idle
    }

    private func actionRequired(
        for reason: CurrentRegionResolution.UnavailableReason,
    ) -> ActionRequired? {
        guard case let .location(locationReason) = reason else { return nil }
        switch locationReason {
            case .preciseLocationDisabled:
                return .preciseLocation
            case let .authorizationUnavailable(status):
                switch status {
                    case .denied, .restricted: return .locationAccess
                    case .always, .whenInUse, .notDetermined: return nil
                }
            case .timeout, .providerFailure, .cancellation:
                return nil
        }
    }

    #if DEBUG
        /// Seeds a deterministic presentation for previews and image snapshots.
        @_spi(Testing) public func presentForTesting(
            region: Region,
            greeting: Presentation.Greeting,
        ) {
            state = .presenting(Presentation(region: region, greeting: greeting))
        }

        /// Seeds the delayed locating accessory without running Core Location.
        @_spi(Testing) public func showLocatingForTesting() {
            state = .locating(showsProgress: true)
        }

        /// Seeds an actionable location-access failure without Core Location.
        @_spi(Testing) public func showLocationAccessActionForTesting() {
            state = .actionRequired(.locationAccess)
        }

        /// Seeds an actionable Precise Location failure without Core Location.
        @_spi(Testing) public func showPreciseLocationActionForTesting() {
            state = .actionRequired(.preciseLocation)
        }
    #endif
}
