import CloudKit
import Testing
@testable import WhereCore

struct CloudKitDataCompatibilityTransportTests {
    private let account = ScriptedSharedDataCompatibilityTransport.account

    @Test func legacyZoneBootstrapsZeroRegardlessOfPreferredMajor() async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: true)
        let transport = CloudKitDataCompatibilityTransport(database: database)
        let state = try await transport.initialize(accountID: account, newAccountMajor: 3)
        #expect(state.requiredMajor == 0)
        #expect(await database.committedSaves == 1)
    }

    @Test func failedSharedInspectionNeverInitializesANewAccount() async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: false)
        await database.failZoneListing(CKError(.networkUnavailable))
        let transport = CloudKitDataCompatibilityTransport(database: database)
        await #expect(throws: CKError.self) { try await transport.initialize(
            accountID: account,
            newAccountMajor: 1,
        ) }
        #expect(await database.committedSaves == 0)
    }

    @Test func concurrentInitializationAdoptsTheConditionalWriteWinner() async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: false)
        let first = CloudKitDataCompatibilityTransport(database: database)
        let second = CloudKitDataCompatibilityTransport(database: database)
        let gate = CompatibilityTestGate()
        await database.holdSave(gate)
        let pending = Task { try await first.initialize(accountID: account, newAccountMajor: 1) }
        await gate.waitUntilEntered()
        let winner = try await second.initialize(accountID: account, newAccountMajor: 2)
        await gate.resume()
        #expect(try await pending.value == winner)
        #expect(winner.requiredMajor == 2)
        #expect(await database.committedSaves == 1)
    }

    @Test func staleActivationCannotOverwriteAConcurrentHigherMajor() async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: true)
        let first = CloudKitDataCompatibilityTransport(database: database)
        let second = CloudKitDataCompatibilityTransport(database: database)
        let original = try await first.initialize(accountID: account, newAccountMajor: 1)
        let gate = CompatibilityTestGate()
        await database.holdSave(gate)
        let pending = Task { try await first.advance(from: original, to: 1) }
        await gate.waitUntilEntered()
        let winner = try await second.advance(from: original, to: 2)
        await gate.resume()
        await #expect(throws: DataCompatibilityError.concurrentChange) { try await pending.value }
        #expect(try await database.head(accountID: account) == winner)
        #expect(await database.committedSaves == 2)
    }

    @Test func lostCreationResponseIsRecoveredByVerification() async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: false)
        let transport = CloudKitDataCompatibilityTransport(database: database)
        await database.loseSaveResponse(CKError(.networkFailure))
        await #expect(throws: CKError.self) { try await transport.initialize(
            accountID: account,
            newAccountMajor: 1,
        ) }
        #expect(try await transport.initialize(accountID: account, newAccountMajor: 2)
            .requiredMajor == 1)
        #expect(await database.committedSaves == 1)
    }

    @Test func accountChangeDuringEstablishedHeadReadRejectsInitialization() async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: false)
        let transport = CloudKitDataCompatibilityTransport(database: database)
        let preparation = CompatibilityTestGate()
        await database.holdPreparation(preparation)
        let pending = Task { try await transport.initialize(accountID: account, newAccountMajor: 1)
        }
        await preparation.waitUntilEntered()
        _ = try await database.saveHead(accountID: account, requiredMajor: 1, expectedRevision: nil)
        let head = CompatibilityTestGate()
        await database.holdHead(head)
        await preparation.resume()
        await head.waitUntilEntered()
        await database.switchAccount()
        await head.resume()
        await #expect(throws: DataCompatibilityError.accountChanged) { try await pending.value }
    }
}
