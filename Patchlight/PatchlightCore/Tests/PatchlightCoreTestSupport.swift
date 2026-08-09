import Foundation
import PatchlightCore
@_spi(Testing) import StuffCore

enum PatchlightCoreTestSupport {
    static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeScope(
        name: String,
        accountID: PatchlightAccountID = PatchlightAccountID(rawValue: 42),
        credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
    ) throws -> (scope: PatchlightScope, root: URL, credentials: InMemoryCredentialStore) {
        let root = try temporaryDirectory(name)
        let scope = try PatchlightScope.make(
            accountID: accountID,
            rootURL: root,
            credentialStore: credentials,
            cacheCapacity: .fiveGB,
        )
        return (scope, root, credentials)
    }

    static var repositoryID: RepositoryID {
        RepositoryID(rawValue: 7)
    }

    static var pullRequestID: PullRequestID {
        PullRequestID(repository: repositoryID, number: 19)
    }

    static func objectID(_ character: Character = "a") -> GitObjectID {
        GitObjectID(rawValue: String(repeating: String(character), count: 40))
    }
}
