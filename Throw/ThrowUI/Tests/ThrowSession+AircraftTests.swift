import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionAircraftTests {
    @Test func failedSourcePersistenceKeepsTheOldSourceAndCredentialLive() async throws {
        let preferenceStore = FailableThrowPreferenceStore(failsSave: true)
        let credentialStore = FailableAircraftCredentialStore(credentials: [:])
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: credentialStore,
        )
        let previousHealth = session.feedHealth
        let query = try session.aircraftQuery()
        await session.airAndSpaceRuntime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: session.labelMode,
            activationGeneration: 1,
        )
        session.activePollingSignature = try PollingSignature(
            configuration: .adsbLol,
            query: query,
        )
        let replacement = try AircraftCredential(secret: "fr24-replacement-1234")
        let configuration = AircraftSourceConfiguration.flightradar24(
            Flightradar24Configuration(
                pollingInterval: .defaultValue,
                credentialID: .flightradar24,
            ),
        )

        let applied = await session.useSource(ValidatedAircraftSourceDraft(
            configuration: configuration,
            replacementCredential: replacement,
        ))

        #expect(applied == false)
        #expect(session.sourceChoice == .adsbLol)
        #expect(session.activePollingSignature?.configuration == .adsbLol)
        #expect(session.feedHealth == previousHealth)
        #expect(session.flightradar24CredentialState == .missing)
        #expect(await credentialStore.credential(for: .flightradar24) == nil)
        #expect(await session.airAndSpaceRuntime.activeSourceKindForTesting() == .adsbLol)
        await session.airAndSpaceRuntime.deactivate(reporting: .idle)
    }

    @Test func failedCredentialDeletionKeepsTheActiveSourceRunning() async throws {
        let credential = try AircraftCredential(secret: "fr24-existing-1234")
        let credentialStore = FailableAircraftCredentialStore(
            credentials: [.flightradar24: credential],
            failsDelete: true,
        )
        let session = ThrowSession.fixture(
            preferenceStore: FailableThrowPreferenceStore(failsSave: false),
            credentialStore: credentialStore,
        )
        let configuration = AircraftSourceConfiguration.flightradar24(
            Flightradar24Configuration(
                pollingInterval: .defaultValue,
                credentialID: .flightradar24,
            ),
        )
        session.selectedSourceConfiguration = configuration
        session.validatedSourceConfiguration = configuration
        session.flightradar24CredentialState = .saved(lastFour: "1234")
        session.activePollingSignature = try PollingSignature(
            configuration: configuration,
            query: session.aircraftQuery(),
        )
        let previousHealth = session.feedHealth

        let deleted = await session.deleteFlightradar24Credential()

        #expect(deleted == false)
        #expect(session.sourceChoice == .flightradar24)
        #expect(session.activePollingSignature?.configuration == configuration)
        #expect(session.feedHealth == previousHealth)
        #expect(session.flightradar24CredentialState == .saved(lastFour: "1234"))
        #expect(await credentialStore.credential(for: .flightradar24) == credential)
    }
}

private enum SourceMutationStoreFailure: Error {
    case save
    case delete
}

private actor FailableThrowPreferenceStore: ThrowPreferenceStore {
    private let failsSave: Bool
    private var preferences = ThrowPreferences.defaultValue

    init(failsSave: Bool) {
        self.failsSave = failsSave
    }

    func load() -> ThrowPreferences {
        preferences
    }

    func save(_ preferences: ThrowPreferences) throws {
        if failsSave { throw SourceMutationStoreFailure.save }
        self.preferences = preferences
    }
}

private actor FailableAircraftCredentialStore: AircraftCredentialStore {
    private var credentials: [AircraftCredentialID: AircraftCredential]
    private let failsDelete: Bool

    init(
        credentials: [AircraftCredentialID: AircraftCredential],
        failsDelete: Bool = false,
    ) {
        self.credentials = credentials
        self.failsDelete = failsDelete
    }

    func state(for id: AircraftCredentialID) -> CredentialState {
        guard let credential = credentials[id] else { return .missing }
        return .saved(lastFour: credential.lastFour)
    }

    func credential(for id: AircraftCredentialID) -> AircraftCredential? {
        credentials[id]
    }

    func save(_ credential: AircraftCredential, for id: AircraftCredentialID) {
        credentials[id] = credential
    }

    func delete(_ id: AircraftCredentialID) throws {
        if failsDelete { throw SourceMutationStoreFailure.delete }
        credentials[id] = nil
    }
}
