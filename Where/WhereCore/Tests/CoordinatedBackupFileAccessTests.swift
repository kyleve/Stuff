import Foundation
import Testing
@testable import WhereCore

struct CoordinatedBackupFileAccessTests {
    @Test func accessesTheSuppliedURLAndPropagatesAccessorFailures() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("archive")
        let storedURL = try CoordinatedBackupFileAccess.write(at: file, options: []) { url in
            try Data([1, 2, 3]).write(to: url)
            return url
        }
        #expect(try CoordinatedBackupFileAccess
            .read(at: storedURL) { try Data(contentsOf: $0) } == Data([
                1,
                2,
                3,
            ]))
        #expect(throws: CocoaError.self) {
            try CoordinatedBackupFileAccess.read(at: storedURL) { _ -> Data in
                throw CocoaError(.fileReadNoPermission)
            }
        }
    }
}
