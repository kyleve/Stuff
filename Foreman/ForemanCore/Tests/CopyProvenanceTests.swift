@_spi(Testing) import ForemanCore
import Foundation
import Testing

struct CopyProvenanceTests {
    @Test func codableRoundTrip() throws {
        let provenance = CopyProvenance(
            kind: .worktree,
            parentRepoID: RepoID(rawValue: "/Users/dev/Development/Main"),
            branch: "feature/x",
        )
        let data = try JSONEncoder().encode(provenance)
        let decoded = try JSONDecoder().decode(CopyProvenance.self, from: data)
        #expect(decoded == provenance)
    }

    @Test func kindEncodesAsItsRawString() throws {
        let provenance = CopyProvenance(
            kind: .clone,
            parentRepoID: RepoID(rawValue: "/x/Main"),
            branch: "b",
        )
        let object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(provenance),
            ) as? [String: Any],
        )
        #expect(object["kind"] as? String == "clone")
        #expect(object["branch"] as? String == "b")
    }

    @Test func differsByEachField() {
        let base = CopyProvenance(
            kind: .worktree,
            parentRepoID: RepoID(rawValue: "/x/Main"),
            branch: "b",
        )
        #expect(base != CopyProvenance(
            kind: .clone,
            parentRepoID: RepoID(rawValue: "/x/Main"),
            branch: "b",
        ))
        #expect(base != CopyProvenance(
            kind: .worktree,
            parentRepoID: RepoID(rawValue: "/x/Other"),
            branch: "b",
        ))
        #expect(base != CopyProvenance(
            kind: .worktree,
            parentRepoID: RepoID(rawValue: "/x/Main"),
            branch: "c",
        ))
    }
}
