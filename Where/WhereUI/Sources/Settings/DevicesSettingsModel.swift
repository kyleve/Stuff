import Foundation
import Observation
import WhereCore

/// View-scoped operations needed by Devices settings, without adding another responsibility to
/// the already broad `WhereSession` type.
@MainActor
struct DevicesSettingsClient {
    let recordingDeviceUpdates: () -> AsyncStream<Void>
    let recordingDevices: () async throws -> [RecordingDeviceConfiguration]
    let setRecordingEnabled: (Bool) async throws -> Void
    let renameRecordingDevice: (RecordingDeviceID, String) async throws -> Void
    let removeRecordingDevice: (RecordingDeviceID) async throws -> Void
    let requestPermission: () async -> Void

    init(
        recordingDeviceUpdates: @escaping () -> AsyncStream<Void>,
        recordingDevices: @escaping () async throws -> [RecordingDeviceConfiguration],
        setRecordingEnabled: @escaping (Bool) async throws -> Void,
        renameRecordingDevice: @escaping (RecordingDeviceID, String) async throws -> Void,
        removeRecordingDevice: @escaping (RecordingDeviceID) async throws -> Void,
        requestPermission: @escaping () async -> Void,
    ) {
        self.recordingDeviceUpdates = recordingDeviceUpdates
        self.recordingDevices = recordingDevices
        self.setRecordingEnabled = setRecordingEnabled
        self.renameRecordingDevice = renameRecordingDevice
        self.removeRecordingDevice = removeRecordingDevice
        self.requestPermission = requestPermission
    }

    init(session: WhereSession) {
        self.init(
            recordingDeviceUpdates: { session.services.dataChangeUpdates() },
            recordingDevices: { try await session.recordingDevices() },
            setRecordingEnabled: { try await session.setRecordingEnabled($0) },
            renameRecordingDevice: { try await session.renameRecordingDevice($0, to: $1) },
            removeRecordingDevice: { try await session.removeRecordingDevice($0) },
            requestPermission: { await session.requestPermission() },
        )
    }
}

/// View-scoped Devices settings state. Refreshes are read-only; commands originate only from
/// explicit row intents, so a CloudKit update can never submit a local recording choice.
@MainActor
@Observable
final class DevicesSettingsModel {
    struct Failure: Identifiable, Equatable {
        enum Context: Equatable {
            case initialLoad
            case operation(deviceID: RecordingDeviceID)
            case refresh
        }

        let id = UUID()
        let context: Context
        let message: String
    }

    enum LoadState {
        case idle
        case loading
        case empty
        case loaded
        case failed(Failure)

        var isReadyForSearchFocus: Bool {
            if case .loaded = self { true } else { false }
        }
    }

    private let client: DevicesSettingsClient
    private(set) var state: LoadState = .idle
    private(set) var rows: [DeviceSettingsRowModel] = []
    private(set) var presentedFailure: Failure?
    @ObservationIgnored private var operationDeviceIDs: Set<RecordingDeviceID> = []

    var isShowingError: Bool {
        get { presentedFailure != nil }
        set { if !newValue { presentedFailure = nil } }
    }

    var presentedFailureCanRetry: Bool {
        presentedFailure?.context == .refresh
    }

    init(session: WhereSession) {
        client = DevicesSettingsClient(session: session)
    }

    init(client: DevicesSettingsClient) {
        self.client = client
    }

    #if DEBUG
        init(
            session: WhereSession,
            configurations: [RecordingDeviceConfiguration],
        ) {
            client = DevicesSettingsClient(session: session)
            apply(configurations)
            state = configurations.isEmpty ? .empty : .loaded
        }

        init(
            client: DevicesSettingsClient,
            configurations: [RecordingDeviceConfiguration],
        ) {
            self.client = client
            apply(configurations)
            state = configurations.isEmpty ? .empty : .loaded
        }
    #endif

    func run() async {
        let updates = client.recordingDeviceUpdates()
        await load(showLoading: true)
        for await _ in updates {
            await load(showLoading: false)
        }
    }

    func retry() async {
        await load(showLoading: true)
    }

    func recordingPreferenceChanged(for row: DeviceSettingsRowModel) async {
        guard row.isCurrent else {
            assertionFailure("A remote device cannot change another installation's preference.")
            return
        }
        await processPendingOperations(for: row)
    }

    func saveNickname(_ row: DeviceSettingsRowModel) async {
        row.requestNicknameSave()
        await processPendingOperations(for: row)
    }

    func remove(_ row: DeviceSettingsRowModel) async {
        row.requestRemoval()
        await processPendingOperations(for: row)
    }

    func requestPermission() async {
        await client.requestPermission()
        await load(showLoading: false)
    }

    private func load(showLoading: Bool) async {
        if showLoading, rows.isEmpty { state = .loading }
        do {
            try await apply(client.recordingDevices())
            state = rows.isEmpty ? .empty : .loaded
            if presentedFailure?.context == .refresh { presentedFailure = nil }
        } catch {
            let failure = Failure(
                context: rows.isEmpty ? .initialLoad : .refresh,
                message: error.localizedDescription,
            )
            if rows.isEmpty { state = .failed(failure) } else { presentedFailure = failure }
        }
    }

    private func processPendingOperations(for row: DeviceSettingsRowModel) async {
        guard operationDeviceIDs.insert(row.id).inserted else { return }
        defer { operationDeviceIDs.remove(row.id) }
        while let operation = row.beginNextOperation() {
            do {
                switch operation {
                    case let .setRecordingEnabled(enabled):
                        try await client.setRecordingEnabled(enabled)
                    case let .rename(nickname):
                        try await client.renameRecordingDevice(row.id, nickname)
                    case .remove:
                        try await client.removeRecordingDevice(row.id)
                }
                row.finish(operation)
                await load(showLoading: false)
                if operation == .remove { return }
            } catch {
                let failure = row.fail(operation, error: error)
                presentedFailure = Failure(
                    context: .operation(deviceID: row.id),
                    message: failure.message,
                )
                await load(showLoading: false)
                return
            }
        }
    }

    private func apply(_ configurations: [RecordingDeviceConfiguration]) {
        let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        rows = configurations.map { configuration in
            if let row = existing[configuration.id] {
                row.update(from: configuration)
                return row
            }
            return DeviceSettingsRowModel(configuration: configuration)
        }
    }
}
