import Foundation

actor BackupKeyAccessGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var hasArrived = false

    func wait() async -> Bool {
        hasArrived = true
        arrival?.resume()
        arrival = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitForArrival() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        continuation?.resume(returning: true)
        continuation = nil
    }
}
