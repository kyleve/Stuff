import Foundation

/// The stable subset of `git lfs ls-files --json` needed before snapshot tests.
public struct GitLFSInventory: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Sendable {
        public let name: String
        public let checkout: Bool

        public init(name: String, checkout: Bool) {
            self.name = name
            self.checkout = checkout
        }
    }

    public let files: [Entry]

    public init(files: [Entry]) {
        self.files = files
    }

    public var unhydratedSnapshotReferences: [String] {
        files.lazy
            .filter { $0.checkout == false }
            .map(\.name)
            .filter { $0.contains("/__Snapshots__/") && $0.hasSuffix(".png") }
            .sorted()
    }
}
