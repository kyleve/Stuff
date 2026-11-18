import Foundation
@testable import WhereCore

actor RecordingRetirementSuspension {
    private var continuation: CheckedContinuation<Void, Never>?
    var isHeld: Bool {
        continuation != nil
    }

    func hold() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

actor SuspendingLocationOutbox: LocationOutbox {
    let suspension = RecordingRetirementSuspension()

    func load() async throws -> [LocationOutboxEntry] {
        await suspension.hold()
        return []
    }

    func save(_: [LocationOutboxEntry]) async throws {}
    func clear() async throws {}
}
