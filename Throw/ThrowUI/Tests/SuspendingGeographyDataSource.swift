import Foundation
import ThrowCore

actor SuspendingGeographyDataSource: GeographyDataSource {
    private(set) var loadCount = 0
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func data() async throws -> Data {
        loadCount += 1
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if isReleased == false {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return Data(
            """
            {"version":2,"coordinateScale":10000,"sources":[{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],"paths":[{"kind":"coastline","detailLevel":"wide","bounds":[369000,-1221000,371000,-1219000],"coordinates":[370000,-1221000,0,2000]}]}
            """.utf8,
        )
    }

    func waitUntilLoadStarts() async {
        guard loadCount == 0 else { return }
        await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
