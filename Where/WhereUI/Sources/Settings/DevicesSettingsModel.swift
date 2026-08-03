import Foundation
import Observation
import WhereCore

/// The Settings-specific surface of the session. Commands report completion only; every row
/// snapshot is obtained through the model's single ordered refresh path.
@MainActor
protocol DevicesSettingsSession: AnyObject {
    var currentRecordingDeviceID: RecordingDeviceID { get }

    func recordingDeviceUpdates() -> AsyncStream<Void>
    func recordingDevices() async throws -> [RecordingDeviceConfiguration]
    func setRecordingEnabled(_ enabled: Bool, for deviceID: RecordingDeviceID) async throws
    func renameRecordingDevice(_ deviceID: RecordingDeviceID, to nickname: String) async throws
    func archiveRecordingDevice(_ deviceID: RecordingDeviceID) async throws
    func requestPermission() async
}

extension WhereSession: DevicesSettingsSession {
    func recordingDeviceUpdates() -> AsyncStream<Void> {
        services.dataChangeUpdates()
    }
}

/// View-scoped Devices settings state. All mutations await the serialized Core
/// controller. Each row owns one operation state and this model drains its
/// accepted intents in order, including a newer toggle made while a write is
/// suspended.
@MainActor
@Observable
final class DevicesSettingsModel {
    struct Failure: Identifiable, Equatable {
        enum Context: Equatable {
            case initialLoad
            case operation(
                deviceID: RecordingDeviceID,
                failure: DeviceSettingsRowModel.OperationFailure,
            )
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

    private struct RefreshFailure {
        let generation: UInt64
        let error: any Error
    }

    private let session: any DevicesSettingsSession
    private(set) var state: LoadState = .idle
    private(set) var rows: [DeviceSettingsRowModel] = []
    private(set) var presentedFailure: Failure?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var requestedRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var completedRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var lastRefreshFailure: RefreshFailure?
    @ObservationIgnored private var committedOperationsAwaitingRefresh: [
        RecordingDeviceID: DeviceSettingsRowModel.Operation
    ] = [:]
    @ObservationIgnored private var rowsNeedingOperationResume: Set<RecordingDeviceID> = []

    var isShowingError: Bool {
        get { presentedFailure != nil }
        set {
            if !newValue { dismissPresentedFailure() }
        }
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

    /// Load once, then stay current with local commits and CloudKit imports
    /// until the owning view disappears and SwiftUI cancels the task.
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

    /// Persist the row's latest recording draft. If another write is already
    /// active, that writer will observe this draft before it exits and submit
    /// it next; no accepted toggle is discarded.
    func recordingPreferenceChanged(for row: DeviceSettingsRowModel) async {
        await processPendingOperations(for: row)
    }

    /// Mark the current nickname draft for an explicit save. A request made
    /// while another row operation is active remains queued.
    func saveNickname(_ row: DeviceSettingsRowModel) async {
        row.requestNicknameSave()
        await processPendingOperations(for: row)
    }

    func archive(_ row: DeviceSettingsRowModel) async {
        guard !row.isCurrent else {
            assertionFailure("The current recording device cannot be archived.")
            return
        }
        row.requestArchive()
        await processPendingOperations(for: row)
    }

    func requestPermission() async {
        await session.requestPermission()
        await load(showLoading: false)
    }

    private func load(showLoading: Bool) async {
        // Keep already rendered rows visible while a manual retry reconciles them. If that read
        // fails again, the user gets another retryable alert instead of a permanent spinner.
        if showLoading, rows.isEmpty { state = .loading }
        do {
            try await refreshConfigurations()
            completeSuccessfulRefresh()
            await resumeOperationsAfterRefresh()
        } catch {
            if rows.isEmpty {
                state = .failed(Failure(
                    context: .initialLoad,
                    message: error.localizedDescription,
                ))
            } else {
                surfaceLoadRefreshFailure(error)
            }
        }
    }

    private func processPendingOperations(for row: DeviceSettingsRowModel) async {
        while let operation = row.beginNextOperation() {
            do {
                switch operation {
                    case let .setRecordingEnabled(enabled):
                        try await session.setRecordingEnabled(enabled, for: row.id)
                    case let .rename(nickname):
                        try await session.renameRecordingDevice(row.id, to: nickname)
                    case .archive:
                        try await session.archiveRecordingDevice(row.id)
                }
            } catch {
                let failure = row.fail(operation, error: error)
                surface(failure, for: row.id)
                // A write can fail after committing. Re-read so the controls
                // show persisted truth while preserving an unsaved nickname
                // draft as the explicit retry path.
                await load(showLoading: false)
                return
            }

            committedOperationsAwaitingRefresh[row.id] = operation
            do {
                // Never apply the snapshot a command happened to observe. A CloudKit import can
                // land while the command is suspended, so all truth is re-read through the same
                // ordered path used by data-change updates. A failed read does not turn a command
                // that already committed into a failed command or cause it to be issued again.
                try await refreshConfigurations()
                completeSuccessfulRefresh()
                rowsNeedingOperationResume.remove(row.id)
                await resumeOperationsAfterRefresh()
                if operation == .archive { return }
            } catch {
                surfaceLoadRefreshFailure(error)
                return
            }
        }
    }

    /// Coalesce concurrent command and data-change refreshes without allowing their actor hops
    /// to apply out of order. A request arriving during a read schedules another pass, ensuring
    /// that pass observes the commit which emitted the request.
    private func refreshConfigurations() async throws {
        let targetGeneration = requestRefresh()
        while completedRefreshGeneration < targetGeneration {
            guard let refreshTask else { continue }
            await refreshTask.value
        }
        if let failure = lastRefreshFailure,
           failure.generation >= targetGeneration
        {
            throw failure.error
        }
    }

    private func requestRefresh() -> UInt64 {
        let (generation, overflow) = requestedRefreshGeneration.addingReportingOverflow(1)
        precondition(!overflow, "Devices Settings refresh generation exhausted UInt64.")
        requestedRefreshGeneration = generation
        if refreshTask == nil {
            refreshTask = Task { @MainActor [weak self] in
                await self?.drainRefreshes()
            }
        }
        return generation
    }

    private func drainRefreshes() async {
        while completedRefreshGeneration < requestedRefreshGeneration {
            let generation = requestedRefreshGeneration
            do {
                let configurations = try await session.recordingDevices()
                completedRefreshGeneration = generation
                guard generation == requestedRefreshGeneration else { continue }
                lastRefreshFailure = nil
                apply(configurations)
            } catch {
                completedRefreshGeneration = generation
                guard generation == requestedRefreshGeneration else { continue }
                lastRefreshFailure = RefreshFailure(generation: generation, error: error)
            }
        }
        refreshTask = nil
    }

    private func apply(_ configurations: [RecordingDeviceConfiguration]) {
        let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        rows = configurations.map { configuration in
            if let row = existing[configuration.id] {
                row.update(from: configuration)
                return row
            }
            return DeviceSettingsRowModel(
                configuration: configuration,
                isCurrent: configuration.id == session.currentRecordingDeviceID,
            )
        }

        let visibleDeviceIDs = Set(rows.map(\.id))
        let committedOperations = committedOperationsAwaitingRefresh
        committedOperationsAwaitingRefresh.removeAll()
        for (deviceID, operation) in committedOperations {
            existing[deviceID]?.finish(operation)
            if operation != .archive, visibleDeviceIDs.contains(deviceID) {
                rowsNeedingOperationResume.insert(deviceID)
            }
        }
    }

    private func completeSuccessfulRefresh() {
        state = rows.isEmpty ? .empty : .loaded
        if presentedFailure?.context == .refresh {
            presentedFailure = nil
        }
    }

    private func resumeOperationsAfterRefresh() async {
        let rowsToResume = rows.filter { rowsNeedingOperationResume.contains($0.id) }
        rowsNeedingOperationResume.removeAll()
        for row in rowsToResume {
            await processPendingOperations(for: row)
        }
    }

    private func surface(
        _ failure: DeviceSettingsRowModel.OperationFailure,
        for deviceID: RecordingDeviceID,
    ) {
        presentedFailure = Failure(
            context: .operation(deviceID: deviceID, failure: failure),
            message: failure.message,
        )
    }

    private func surfaceLoadRefreshFailure(_ error: any Error) {
        guard presentedFailure == nil else { return }
        presentedFailure = Failure(
            context: .refresh,
            message: error.localizedDescription,
        )
    }

    private func dismissPresentedFailure() {
        guard let presentedFailure else { return }
        if case let .operation(deviceID, failure) = presentedFailure.context {
            rows.first(where: { $0.id == deviceID })?.dismiss(failure)
        }
        self.presentedFailure = nil
        if case .operation = presentedFailure.context,
           let lastRefreshFailure
        {
            self.presentedFailure = Failure(
                context: .refresh,
                message: lastRefreshFailure.error.localizedDescription,
            )
        }
    }
}
