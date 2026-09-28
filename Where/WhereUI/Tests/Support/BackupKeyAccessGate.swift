import Foundation

actor BackupKeyAccessGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var hasArrived = false
    private var isOpen = false

    func wait() async -> Bool {
        if isOpen { return true }
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
        isOpen = true
        continuation?.resume(returning: true)
        continuation = nil
    }
}
