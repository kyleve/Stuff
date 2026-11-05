import Foundation
import LifecycleKit
import PeriscopeCore
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore
@_spi(Testing) @testable import WhereUI

/// Two instances model distinct phones. Keychain and server storage never enter the platform
/// backup. Each process rebuilds real sidecars, admission, SwiftData, and scoped services.
@MainActor
final class InstallationLifecycleFixture {
    static let recordingPolicy = DataCompatibilityPolicy(
        current: RecordingEvidencePolicy.version,
        supportedMajors: [1],
    )
    struct HistoryNotOpened: Error {}
    struct ConditionTimedOut: Error {}
    struct ChoiceNotReady: Error {}
    let keychain = ScriptedRecordingIdentityStore()
    let account: InstallationSharedAccount
    let connection: InstallationAccountConnection
    let policy: DataCompatibilityPolicy
    let storeID = DataCompatibilityDataset.StoreID(rawValue: UUID().uuidString)
    private(set) var root: URL
    private var roots: [URL]
    private(set) var process: InstallationProcessFixture?
    private(set) var allocatedIdentities: [UUID] = []
    var instant = Date(timeIntervalSince1970: 1_780_000_000)

    init(account: InstallationSharedAccount, policy: DataCompatibilityPolicy = .foundation) throws {
        self.account = account
        self.policy = policy
        connection = InstallationAccountConnection(account: account)
        root = FileManager.default.temporaryDirectory.appending(path: "installation-\(UUID())")
        roots = [root]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func launch() throws -> InstallationProcessFixture {
        let context = FileInstallationRecordingContextStore(
            identityStore: keychain,
            fileURL: root.appending(path: "Installation/context.json"),
            fileManager: .default,
            systemName: "Fixture iPhone",
            kind: .phone,
            makeUUID: { [unowned self] in
                let id = UUID()
                allocatedIdentities.append(id)
                return id
            },
            now: { [unowned self] in instant },
        )
        let values = try InstallationPreferencesFixture(file: root
            .appending(path: "Preferences.plist"))
        let preferences = WherePreferences(store: values)
        let bootstrap = InstallationBootstrapFixture(
            root: root,
            storeID: storeID,
            account: account,
            connection: connection,
            context: context,
            policy: policy,
        )
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: context,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let next = InstallationProcessFixture(
            context: context,
            values: values,
            bootstrap: bootstrap,
            model: model,
        )
        process = next
        return next
    }

    func stop() async throws {
        guard let process else { return }
        try process.values.flush()
        await process.model.suspendForCompatibility()
        self.process = nil
    }

    func backup() async throws -> InstallationBackupFixture {
        try await stop()
        return try .capture(root)
    }

    /// Reinstall changes only app files. Restore uses the actual backup copier; the caller
    /// separately models whether this physical phone retained, lost, or cannot access Keychain.
    func replaceFiles(with backup: InstallationBackupFixture?) async throws {
        try await stop()
        root = FileManager.default.temporaryDirectory.appending(path: "installation-\(UUID())")
        roots.append(root)
        if let backup { try backup.restore(to: root) }
        else { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    func cleanup() async throws {
        try await stop()
        for root in roots {
            try FileManager.default.removeItem(at: root)
        }
    }

    static func withInstallations(
        count: Int,
        policy: DataCompatibilityPolicy = .foundation,
        operation: ([InstallationLifecycleFixture]) async throws -> Void,
    ) async throws {
        let account = InstallationSharedAccount()
        let phones = try (0 ..< count).map { _ in try Self(account: account, policy: policy) }
        do { try await operation(phones) }
        catch {
            for phone in phones {
                do { try await phone.cleanup() }
                catch { Issue.record(error) }
            }
            throw error
        }
        for phone in phones {
            try await phone.cleanup()
        }
    }

    static func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while try await !predicate() {
            guard ContinuousClock.now < deadline else { throw ConditionTimedOut() }
            await Task.yield()
        }
    }
}

@MainActor
struct InstallationProcessFixture {
    let context: FileInstallationRecordingContextStore
    let values: InstallationPreferencesFixture
    let bootstrap: InstallationBootstrapFixture
    let model: WhereModel

    func reviewChoice(action: HistoryDecision.Action) async throws -> RecordingChoiceReview
        .Proposal
    {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let result = try await services.recordingChoices.review(.init(
            scope: .periods([.init(start: start, end: start.addingTimeInterval(300))]),
            action: action,
        ))
        guard case let .ready(proposal) = result
        else { throw InstallationLifecycleFixture.ChoiceNotReady() }
        return proposal
    }

    func controls() async throws -> RecordingControlSnapshot {
        try await RecordingControlStore(store: store, policy: bootstrap.policy).snapshot()
    }

    func confirmAndStart(recording: Bool) async throws {
        _ = try context.confirmInitialRecording(isEnabled: recording)
        try context.completeSetup()
        model.preferences.hasOnboarded = true
        try await start()
    }

    func start() async throws {
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        let drive = Task { await launcher.run() }
        do {
            try await InstallationLifecycleFixture.waitUntil {
                switch launcher.phase {
                    case .ready, .awaitingGate, .failed: true
                    case .launching, .running: false
                }
            }
            guard launcher.phase.isReady
            else { throw InstallationLifecycleFixture.HistoryNotOpened() }
        } catch {
            await bootstrap.account.releaseInitialSaves()
            launcher.phase.gateHandle?.fail(error)
            drive.cancel()
            await drive.value
            throw error
        }
        await drive.value
        try services.validateDataAccess()
        try values.flush()
    }

    var services: WhereServices {
        get throws {
            guard let services = model.activeScope?.services else {
                throw InstallationLifecycleFixture.HistoryNotOpened()
            }
            return services
        }
    }

    func sample(recordedBy deviceID: RecordingDeviceID) -> LocationSample {
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_780_000_010),
            coordinate: .init(latitude: 40, longitude: -74),
            horizontalAccuracy: 5,
            source: .gpsVisit,
            recordingDeviceID: deviceID,
            recordingDay: nil,
        )
    }

    var store: SwiftDataStore {
        get throws {
            guard let store = bootstrap.store
            else { throw InstallationLifecycleFixture.HistoryNotOpened() }
            return store
        }
    }
}

@MainActor
final class InstallationBootstrapFixture: WhereScopeAssembling {
    let root: URL
    let storeID: DataCompatibilityDataset.StoreID
    let account: InstallationSharedAccount
    let connection: InstallationAccountConnection
    let context: FileInstallationRecordingContextStore
    let policy: DataCompatibilityPolicy
    private(set) var store: SwiftDataStore?
    let remoteChanges = ScriptedStoreRemoteChangeSource()
    private(set) var locationSource: ScriptedLocationSource?
    private var coordinator: DataCompatibilityCoordinator?
    private var services: WhereServices?

    init(
        root: URL,
        storeID: DataCompatibilityDataset.StoreID,
        account: InstallationSharedAccount,
        connection: InstallationAccountConnection,
        context: FileInstallationRecordingContextStore,
        policy: DataCompatibilityPolicy,
    ) {
        self.root = root; self.storeID = storeID; self.account = account; self.context = context
        self.connection = connection
        self.policy = policy
    }

    func prepareLocation() {}
    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }

    func sharedEvidenceDraftQueue() -> (any SharedEvidenceDraftQueuing)? {
        FileSharedEvidenceDraftQueue(directory: root.appending(path: "PendingSharedEvidence"))
    }

    func prepareDataCompatibility() -> DataCompatibilityCoordinator? {
        if let coordinator { return coordinator }
        let file = root.appending(path: "History/Where.store")
        let preparation = DataCompatibilityStorePreparation(
            hasExistingHistory: FileManager.default.fileExists(atPath: file.path),
            makeStore: { [weak self] in
                guard let self else { throw InstallationLifecycleFixture.HistoryNotOpened() }
                return try await openStore(at: file)
            },
        )
        let created = DataCompatibilityCoordinator(
            storePreparation: preparation,
            source: .cloudKit(
                storeID: storeID,
                transport: CloudKitDataCompatibilityTransport(database: connection),
                cache: FileDataCompatibilityCache(fileURL: root
                    .appending(path: "Compatibility/cache.json")),
            ),
            policy: policy,
            activationReadiness: .pendingValidation,
        )
        coordinator = created
        return created
    }

    private func openStore(at file: URL) async throws -> SwiftDataStore {
        if let store { return store }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let schema = Schema(SwiftDataStore.inspectorModelTypes)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                url: file,
                cloudKitDatabase: .none,
            )],
        )
        let created = SwiftDataStore.inMemory(
            modelContainer: container,
            remoteChangeSource: remoteChanges,
        )
        store = created
        await account.markMirrorCreated()
        return created
    }

    func makeServices() async throws -> WhereServices {
        if let services { await services.retireCompatibilityScope() }
        guard let coordinator = prepareDataCompatibility()
        else { throw InstallationLifecycleFixture.HistoryNotOpened() }
        let access = try await coordinator.refresh()
        let locationSource = ScriptedLocationSource(authorizationStatus: .always)
        self.locationSource = locationSource
        let created = try await WhereServices.make(
            access: access,
            locationSource: locationSource,
            installationContext: context.resolve(),
            aggregator: DayAggregator(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
            importRecoveryPersistence: context,
            now: { Date() },
        )
        services = created
        return created
    }

    func discoverRecordingDevices() async throws -> [RecordingDevice] {
        guard let coordinator = prepareDataCompatibility()
        else { throw InstallationLifecycleFixture.HistoryNotOpened() }
        return try await coordinator.refresh().store.recordingDevices()
    }

    func withdrawHistoryOutputs() async {
        await services?.retireCompatibilityScope()
    }
}
