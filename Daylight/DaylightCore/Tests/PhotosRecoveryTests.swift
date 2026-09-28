@testable import DaylightCore
import Foundation
import Testing

struct PhotosRecoveryTests {
    @Test func definiteFailureRetriesButUnknownOutcomeDoesNot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let date = Date(timeIntervalSince1970: 10000)
        let failure = PhotosSaveFailure(message: "Permission denied")
        #expect(try PhotosRecovery
            .failure(failure, originalURL: url, recorded: nil, now: date) == .retry(
                date.addingTimeInterval(30),
                "Permission denied",
            ))
        #expect(try PhotosRecovery.failure(
            DaylightError.interrupted,
            originalURL: url,
            recorded: nil,
            now: date,
        ) == .ambiguous)
        #expect(try PhotosRecovery.failure(
            DaylightError.interrupted,
            originalURL: url,
            recorded: "saved",
            now: date,
        ) == .saving("saved"))
    }

    @Test func failureAfterCommitRetainsSidecarForReconciliation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let receipt = url.deletingPathExtension().appendingPathExtension("photos-receipt")
        defer {
            do { try FileManager.default.removeItem(at: receipt) } catch { Issue.record(error) }
        }
        try Data("saved".utf8).write(to: receipt)
        #expect(try PhotosRecovery.failure(
            DaylightError.interrupted,
            originalURL: url,
            recorded: nil,
            now: Date(),
        ) == .saving("saved"))
    }
}
