import Foundation
import WhereCore

/// The complete onboarding-restore lifecycle, including its irreversible commit boundary.
///
/// Keeping selection, strategy, and committed summary in one value prevents onboarding from
/// accidentally presenting the importer again after an archive has already changed the store.
struct OnboardingRestoreSelection {
    struct ReadyImport {
        let url: URL
        let strategy: BackupCoordinator.ImportStrategy
    }

    private struct ScopedArchive {
        let url: URL
        let hasScopedAccess: Bool

        func stopAccessingSecurityScopedResource() {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private enum State {
        case none
        case choosingStrategy(ScopedArchive)
        case ready(ScopedArchive, BackupCoordinator.ImportStrategy)
        case committed(BackupCoordinator.ImportSummary)
    }

    private var state: State = .none

    static let recommendedStrategy = BackupCoordinator.ImportStrategy.merge

    init() {}

    init(url: URL, hasScopedAccess: Bool) {
        state = .choosingStrategy(ScopedArchive(url: url, hasScopedAccess: hasScopedAccess))
    }

    var selectedURL: URL? {
        switch state {
            case .none, .committed: nil
            case let .choosingStrategy(archive), let .ready(archive, _): archive.url
        }
    }

    var strategy: BackupCoordinator.ImportStrategy? {
        if case let .ready(_, strategy) = state { strategy } else { nil }
    }

    var readyImport: ReadyImport? {
        if case let .ready(archive, strategy) = state {
            ReadyImport(url: archive.url, strategy: strategy)
        } else {
            nil
        }
    }

    /// Replace deliberately reopens recording Off in a new data epoch. Merge and the ordinary
    /// onboarding path may retain authority already discovered in the account.
    var permitsPreservingExistingRecorder: Bool {
        strategy != .replace
    }

    var committedSummary: BackupCoordinator.ImportSummary? {
        if case let .committed(summary) = state { summary } else { nil }
    }

    mutating func select(url: URL, hasScopedAccess: Bool) {
        discardUncommittedSelection()
        guard committedSummary == nil else {
            assertionFailure("A committed onboarding import cannot select another archive.")
            return
        }
        state = .choosingStrategy(ScopedArchive(url: url, hasScopedAccess: hasScopedAccess))
    }

    mutating func choose(_ strategy: BackupCoordinator.ImportStrategy) {
        switch state {
            case let .choosingStrategy(archive), let .ready(archive, _):
                state = .ready(archive, strategy)
            case .none, .committed:
                assertionFailure("A restore strategy requires an uncommitted archive selection.")
        }
    }

    /// Cross the irreversible import boundary, release the file, and retain its exact summary.
    mutating func markCommitted(_ summary: BackupCoordinator.ImportSummary) {
        switch state {
            case let .ready(archive, _):
                archive.stopAccessingSecurityScopedResource()
                state = .committed(summary)
            case let .committed(existing):
                precondition(existing == summary, "A committed import summary cannot change.")
            case .none, .choosingStrategy:
                preconditionFailure("An import can commit only after its strategy is fixed.")
        }
    }

    /// Cancel or roll back only while the archive is still reversible. A committed summary is
    /// deliberately retained so later onboarding work cannot reopen the importer.
    mutating func discardUncommittedSelection() {
        switch state {
            case let .choosingStrategy(archive), let .ready(archive, _):
                archive.stopAccessingSecurityScopedResource()
                state = .none
            case .none, .committed:
                break
        }
    }
}

/// A backup committed during onboarding, but a later device-setup operation failed.
/// The summary makes that irreversible boundary available to terminal launch presentation.
struct OnboardingCommittedImportSetupError: LocalizedError {
    let summary: BackupCoordinator.ImportSummary
    let underlying: any Error

    var errorDescription: String? {
        String(localized: .backupImportSetupTitle)
    }
}
