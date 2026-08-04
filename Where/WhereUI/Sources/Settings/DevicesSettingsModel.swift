import Foundation
import Observation
import WhereCore

@MainActor
protocol DevicesSettingsSession: AnyObject {
    var currentRecordingDeviceID: RecordingDeviceID { get }
    func recordingDeviceUpdates() -> AsyncStream<Void>
    func recordingDevices() async throws -> [RecordingDeviceConfiguration]
    func setRecordingEnabled(_ enabled: Bool) async throws
    func renameRecordingDevice(_ deviceID: RecordingDeviceID, to nickname: String) async throws
    func removeRecordingDevice(_ deviceID: RecordingDeviceID) async throws
    func requestPermission() async
}

extension WhereSession: DevicesSettingsSession {
    func recordingDeviceUpdates() -> AsyncStream<Void> {
        services.dataChangeUpdates()
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

    private let session: any DevicesSettingsSession
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

    init(session: any DevicesSettingsSession) {
        self.session = session
    }

    #if DEBUG
        init(
            session: any DevicesSettingsSession,
            configurations: [RecordingDeviceConfiguration],
        ) {
            self.session = session
            apply(configurations)
            state = configurations.isEmpty ? .empty : .loaded
        }
    #endif

    func run() async {
        let updates = session.recordingDeviceUpdates()
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
        await session.requestPermission()
        await load(showLoading: false)
    }

    private func load(showLoading: Bool) async {
        if showLoading, rows.isEmpty { state = .loading }
        do {
            try await apply(session.recordingDevices())
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
                        try await session.setRecordingEnabled(enabled)
                    case let .rename(nickname):
                        try await session.renameRecordingDevice(row.id, to: nickname)
                    case .remove:
                        try await session.removeRecordingDevice(row.id)
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
