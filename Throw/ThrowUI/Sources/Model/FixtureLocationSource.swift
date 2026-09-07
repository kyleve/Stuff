import Foundation
import ThrowCore

@MainActor
final class FixtureLocationSource: ThrowLocationSource {
    nonisolated let events: AsyncStream<LocationEvent>
    private nonisolated let continuation: AsyncStream<LocationEvent>.Continuation
    private let fix: LocationFix

    init(fix: LocationFix) {
        self.fix = fix
        let pair = AsyncStream.makeStream(
            of: LocationEvent.self,
            bufferingPolicy: .bufferingNewest(4),
        )
        events = pair.stream
        continuation = pair.continuation
    }

    func requestWhenInUseAuthorization() {
        continuation.yield(.authorization(.whenInUse))
    }

    func startUpdates() {
        continuation.yield(.fix(fix))
    }

    func stopUpdates() {}

    deinit {
        continuation.finish()
    }
}
