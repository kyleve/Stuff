import Foundation
import Observation
import WhereCore

/// View-scoped Devices settings state. All mutations await the serialized Core
/// controller and restore the last confirmed value when a write fails.
@MainActor
@Observable
final class DevicesSettingsModel {
    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let session: WhereSession
    private(set) var state: LoadState = .idle
    private(set) var rows: [DeviceSettingsRowModel] = []
    var errorMessage: String?

    var isShowingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue { errorMessage = nil }
        }
    }

    init(session: WhereSession) {
        self.session = session
    }

    #if DEBUG
        init(
            session: WhereSession,
            configurations: [RecordingDeviceConfiguration],
        ) {
            self.session = session
            state = .loaded
            apply(configurations)
        }
    #endif

    /// Load once, then stay current with local commits and CloudKit imports
    /// until the owning view disappears and SwiftUI cancels the task.
    func run() async {
        await load(showLoading: true)
        for await _ in session.services.dataChangeUpdates() {
            if Task.isCancelled { return }
            await load(showLoading: false)
        }
    }

    func retry() async {
        await load(showLoading: true)
    }

    func setEnabled(
        _ enabled: Bool,
        row: DeviceSettingsRowModel,
    ) async {
        guard !row.isBusy, enabled != row.confirmedIsEnabled else { return }
        row.isBusy = true
        defer { row.isBusy = false }
        do {
            let configurations = try await session.setRecordingEnabled(enabled, for: row.id)
            apply(configurations)
        } catch {
            row.isEnabled = row.confirmedIsEnabled
            surface(error)
        }
    }

    func rename(_ row: DeviceSettingsRowModel) async {
        guard !row.isBusy else { return }
        row.isBusy = true
        defer { row.isBusy = false }
        do {
            let nickname = row.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            let configurations = try await session.renameRecordingDevice(
                row.id,
                to: nickname,
            )
            row.nickname = nickname
            apply(configurations)
        } catch {
            row.nickname = row.confirmedNickname
            surface(error)
            await load(showLoading: false)
        }
    }

    func archive(_ row: DeviceSettingsRowModel) async {
        guard !row.isCurrent, !row.isBusy else { return }
        row.isBusy = true
        defer { row.isBusy = false }
        do {
            let configurations = try await session.archiveRecordingDevice(row.id)
            apply(configurations)
        } catch {
            surface(error)
        }
    }

    func requestPermission() async {
        await session.requestPermission()
        await load(showLoading: false)
    }

    private func load(showLoading: Bool) async {
        if showLoading { state = .loading }
        do {
            try await apply(session.recordingDevices())
            state = .loaded
        } catch {
            if rows.isEmpty {
                state = .failed(error.localizedDescription)
            } else {
                surface(error)
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
            return DeviceSettingsRowModel(
                configuration: configuration,
                isCurrent: configuration.id == session.currentRecordingDeviceID,
            )
        }
    }

    private func surface(_ error: any Error) {
        errorMessage = error.localizedDescription
    }
}
