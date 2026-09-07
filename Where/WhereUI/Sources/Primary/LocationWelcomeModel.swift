import Observation
import RegionKit
import WhereCore

/// Presentation state for the live-region welcome on the Locations tab.
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

    public private(set) var presentation: Presentation?

    private let resolver: CurrentRegionResolver
    private let preferences: WherePreferences
    private var resolutionSequence: UInt64 = 0

    init(services: WhereServices, preferences: WherePreferences) {
        resolver = services.currentRegion
        self.preferences = preferences
    }

    /// Resolves a fresh welcome while the Locations root is visible.
    func resolve() async {
        guard preferences.showsLocationWelcome, presentation == nil else { return }
        let (sequence, overflow) = resolutionSequence.addingReportingOverflow(1)
        precondition(!overflow, "Location welcome resolution sequence exhausted UInt64.")
        resolutionSequence = sequence

        guard let region = await resolver.resolve() else { return }
        guard
            !Task.isCancelled,
            preferences.showsLocationWelcome,
            sequence == resolutionSequence,
            presentation == nil
        else { return }
        let previous = preferences.lastWelcomedRegion
        guard region != previous else { return }
        presentation = Presentation(
            region: region,
            greeting: previous == nil ? .first : .returnVisit,
        )
    }

    func dismiss() {
        guard let presentation else { return }
        preferences.lastWelcomedRegion = presentation.region
        self.presentation = nil
    }

    #if DEBUG
        /// Seeds a deterministic state for previews and image snapshots.
        @_spi(Testing) public func presentForTesting(
            region: Region,
            greeting: Presentation.Greeting,
        ) {
            presentation = Presentation(region: region, greeting: greeting)
        }
    #endif
}
