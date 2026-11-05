#if DEBUG
    import Foundation
    @_spi(Testing) import WhereCore

    /// Synchronous fixture that uses the same historical source protocol as the scene.
    @MainActor
    final class FixtureResolutionSource: ResolutionSource {
        let resolutionState: ResolutionSourceState

        init(scan: DataIssueScanResult, year: Int) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            do {
                resolutionState = try .loaded(.init(yearScans: [year: scan], calendar: calendar))
            } catch {
                preconditionFailure("Invalid resolution fixture: \(error)")
            }
        }

        init(state: ResolutionSourceState) {
            resolutionState = state
        }

        func refreshResolution() async {}
    }
#endif
