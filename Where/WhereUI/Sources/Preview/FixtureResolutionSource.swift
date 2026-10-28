#if DEBUG
    import RegionKit
    import WhereCore

    /// Synchronous fixture that uses the same source protocol as the scene.
    @MainActor
    final class FixtureResolutionSource: ResolutionSource {
        let resolutionState: ResolutionSourceState

        init(scan: DataIssueScanResult) {
            resolutionState = .loaded(scan)
        }

        func refreshResolution(year _: Int, primaryRegions _: [Region]) async {}
    }
#endif
