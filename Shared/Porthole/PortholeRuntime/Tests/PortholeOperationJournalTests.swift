import Foundation
import PortholeRuntime
import Testing

struct PortholeOperationJournalTests {
    @Test func reloadMarksStartedOperationUncertain() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let url = directory.appendingPathComponent("operations.json")
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        let journal = PortholeOperationJournal(url: url)
        try await journal.write(PortholeOperationRecord(invocation: invocation, status: .started))
        let restored = PortholeOperationJournal(url: url)
        #expect(try await restored.record(for: invocation.id)?.status == .uncertain)
    }
}
