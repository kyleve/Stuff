@testable import InstallerKitUI
import Testing

@MainActor
struct InstallerKitUIMountMatrixTests {
    @Test func failureCard() async throws {
        try await MountMatrix.run(
            bundle: "InstallerKitUISnapshotTests",
            suites: [
                MountMatrix.Suite(
                    file: "UpdateFailureCardSnapshotTests.swift",
                    test: "failure()",
                    cases: UpdateFailureCard.snapshots,
                ),
            ],
            sourcePath: #filePath,
        )
    }
}
