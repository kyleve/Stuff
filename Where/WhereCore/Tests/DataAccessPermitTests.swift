import Testing
@testable import WhereCore

struct DataAccessPermitTests {
    @Test func retirementIsIrrevocableAndDoesNotRetireANewScope() throws {
        let retired = DataAccessPermit()
        try retired.validate()
        retired.revoke()
        retired.revoke()
        #expect(throws: DataAccessPermit.AccessError.revoked) { try retired.validate() }
        #expect(throws: DataAccessPermit.AccessError.revoked) {
            try retired.commitWhileValid { Issue.record("A retired scope committed.") }
        }
        try DataAccessPermit().validate()
    }

    @Test func suspendedReadCannotReturnThroughARetiredPermit() async throws {
        let permit = DataAccessPermit()
        let gate = CompatibilityTestGate()
        let read = Task {
            try await permit.withAccess {
                await gate.suspend()
                return 42
            }
        }
        await gate.waitUntilEntered()
        permit.revoke()
        await gate.resume()
        await #expect(throws: DataAccessPermit.AccessError.revoked) { try await read.value }
    }

    @Test func nestedAccessCannotReplaceTheCallersPermit() async throws {
        let first = DataAccessPermit()
        let second = DataAccessPermit()
        try await first.withAccess {
            try await first.withAccess { #expect(DataAccessPermit.current === first) }
            await #expect(throws: DataAccessPermit.AccessError.differentScope) {
                try await second.withAccess { Issue.record("Another scope replaced the caller.") }
            }
            #expect(DataAccessPermit.current === first)
        }
        #expect(DataAccessPermit.current == nil)
    }
}
