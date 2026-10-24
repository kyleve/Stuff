import Foundation
@testable import InstallerKit

@MainActor
final class UpdateModelClient: UpdateFetching {
    enum Failure: Error { case offline }
    var result: Result<UpdateCatalog, Failure>
    var held = false
    private(set) var fetchCount = 0
    private var continuations: [CheckedContinuation<UpdateCatalog, any Error>] = []
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var expectedRequests = 0

    init(_ catalog: UpdateCatalog) {
        result = .success(catalog)
    }

    func fetch(from _: URL) async throws -> UpdateCatalog {
        fetchCount += 1
        if !held { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            if continuations.count >= expectedRequests {
                requestWaiter?.resume()
                requestWaiter = nil
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard continuations.count < count else { return }
        expectedRequests = count
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func resume(_ index: Int, catalog: UpdateCatalog) {
        continuations[index].resume(returning: catalog)
    }

    func resume(_ index: Int, error: any Error) {
        continuations[index].resume(throwing: error)
    }
}
