import PatchlightCore
import Testing

struct IdentifiersTests {
    @Test func pullRequestStorageKeyKeepsRepositoryIdentity() {
        let id = PullRequestID(repository: RepositoryID(rawValue: 92), number: 17)
        #expect(id.storageKey == "92:17")
    }

    @Test func validatesAndNormalizesWireObjectIDs() throws {
        let uppercase = String(repeating: "A", count: 40)
        #expect(try GitObjectID(validating: uppercase).rawValue == uppercase.lowercased())
        #expect(throws: GitObjectIDError.invalidWireValue) {
            try GitObjectID(validating: "not-an-object-id")
        }
    }
}
