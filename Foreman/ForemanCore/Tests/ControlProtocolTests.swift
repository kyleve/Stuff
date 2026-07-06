@_spi(Testing) import ForemanCore
import Foundation
import Testing

/// The control socket is a hand-written contract shared with the TypeScript
/// MCP client, so these lock the exact JSON shape (keys + discriminators), not
/// just Swift-to-Swift round-tripping.
@MainActor
struct ControlProtocolTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
    }

    // MARK: - Requests

    @Test func describeRequestIsJustACommand() throws {
        let object = try json(ControlRequest.describe)
        #expect(object["command"] as? String == "describe")
        #expect(object.count == 1)
    }

    @Test func adoptRequestCarriesPathAndProvenance() throws {
        let request = ControlRequest.adopt(
            path: "/Users/dev/Development/Copy",
            provenance: CopyProvenanceDTO(
                kind: "worktree",
                parentRepoID: "/Users/dev/Development/Main",
                branch: "feature",
            ),
        )
        let object = try json(request)
        #expect(object["command"] as? String == "adopt")
        #expect(object["path"] as? String == "/Users/dev/Development/Copy")
        let provenance = try #require(object["provenance"] as? [String: Any])
        #expect(provenance["kind"] as? String == "worktree")
        #expect(provenance["parentRepoID"] as? String == "/Users/dev/Development/Main")
        #expect(provenance["branch"] as? String == "feature")
    }

    @Test func requestsRoundTrip() throws {
        let requests: [ControlRequest] = [
            .describe,
            .adopt(
                path: "/x/Copy",
                provenance: CopyProvenanceDTO(kind: "clone", parentRepoID: "/x/Main", branch: "b"),
            ),
            .removeCopy(path: "/x/Copy"),
        ]
        for request in requests {
            let decoded = try decoder.decode(ControlRequest.self, from: encoder.encode(request))
            #expect(decoded == request)
        }
    }

    // MARK: - Responses

    @Test func successResponsesCarryOkTrueAndAKind() throws {
        let describe = try json(ControlResponse.describe(
            DescribeResultDTO(scanDirectory: "/x", repos: []),
        ))
        #expect(describe["ok"] as? Bool == true)
        #expect(describe["kind"] as? String == "describe")

        let removed = try json(ControlResponse.removed(path: "/x/Copy"))
        #expect(removed["ok"] as? Bool == true)
        #expect(removed["kind"] as? String == "removed")
        #expect(removed["path"] as? String == "/x/Copy")
    }

    @Test func failureResponseCarriesOkFalseAndError() throws {
        let object = try json(ControlResponse.failure(message: "nope"))
        #expect(object["ok"] as? Bool == false)
        #expect(object["error"] as? String == "nope")
        #expect(object["kind"] == nil)
    }

    @Test func responsesRoundTrip() throws {
        let status = RepoStatusDTO(
            id: "/x/Copy",
            name: "Copy",
            path: "/x/Copy",
            enabled: true,
            workerState: "running",
            pid: 4321,
            failureReason: nil,
            provenance: CopyProvenanceDTO(kind: "worktree", parentRepoID: "/x/Main", branch: "b"),
        )
        let responses: [ControlResponse] = [
            .describe(DescribeResultDTO(scanDirectory: "/x", repos: [status])),
            .repo(status),
            .removed(path: "/x/Copy"),
            .failure(message: "boom"),
        ]
        for response in responses {
            let decoded = try decoder.decode(ControlResponse.self, from: encoder.encode(response))
            #expect(decoded == response)
        }
    }

    // MARK: - DTO mapping

    @Test func provenanceDTORoundTripsThroughTheModel() throws {
        let dto = CopyProvenanceDTO(kind: "clone", parentRepoID: "/x/Main", branch: "b")
        let model = try dto.model()
        #expect(model.kind == .clone)
        #expect(model.parentRepoID == RepoID(rawValue: "/x/Main"))
        #expect(model.branch == "b")
        #expect(CopyProvenanceDTO(model) == dto)
    }

    @Test func invalidProvenanceKindThrows() {
        let dto = CopyProvenanceDTO(kind: "sideways", parentRepoID: "/x/Main", branch: "b")
        #expect(throws: ControlError.invalidProvenanceKind("sideways")) {
            try dto.model()
        }
    }

    @Test func repoStatusReflectsAFailedWorker() throws {
        let base = try makeTemporaryDirectory()
        let logs = base.appendingPathComponent("logs")
        let repo = makeStubRepo(
            scanned: ScannedRepo(name: "Copy", rootURL: base.appendingPathComponent("Copy")),
            logDirectory: logs,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            provenance: CopyProvenance(
                kind: .worktree,
                parentRepoID: RepoID(rawValue: "/x/Main"),
                branch: "b",
            ),
        )
        repo.worker.recordStartFailure(reason: "kaboom")

        let status = RepoStatusDTO(repo: repo)
        #expect(status.name == "Copy")
        #expect(status.workerState == "failed")
        #expect(status.failureReason == "kaboom")
        #expect(status.pid == nil)
        #expect(status.provenance?.kind == "worktree")
        #expect(status.provenance?.branch == "b")
    }
}
