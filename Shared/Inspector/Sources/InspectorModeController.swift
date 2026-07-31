import Foundation
import Observation

/// Persists the next application runtime and any store-family recovery that
/// must finish before the next process constructs one.
///
/// The control value lives in its own defaults suite, separate from the
/// application domain Inspector exposes for editing. Clearing app preferences
/// therefore cannot strand or unexpectedly exit the developer tool, or erase
/// a pending recovery request.
@MainActor
@Observable
public final class InspectorModeController {
    public enum NextLaunch: Equatable, Sendable {
        case regularApplication
        case inspector
    }

    public private(set) var nextLaunch: NextLaunch
    public private(set) var pendingStoreErasureError: String?

    private let userDefaults: UserDefaults
    private static let enabledKey = "inspector.nextLaunch.enabled"
    private static let pendingStoreErasuresKey = "inspector.pendingStoreErasures"

    private struct PendingStoreErasure: Codable, Hashable {
        let storeURL: URL
        let storageRootURL: URL

        private enum CodingKeys: String, CodingKey {
            case storeURL = "store_url"
            case storageRootURL = "storage_root_url"
        }
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        nextLaunch = userDefaults.bool(forKey: Self.enabledKey)
            ? .inspector
            : .regularApplication
    }

    /// Build the dedicated persistent controller for one application.
    public convenience init(applicationIdentifier: String) {
        let suiteName = "\(applicationIdentifier).inspector-control"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to open Inspector defaults suite \(suiteName)")
        }
        self.init(userDefaults: userDefaults)
    }

    public func enterInspectorOnNextLaunch() {
        userDefaults.set(true, forKey: Self.enabledKey)
        nextLaunch = .inspector
    }

    public func useRegularApplicationOnNextLaunch() {
        userDefaults.removeObject(forKey: Self.enabledKey)
        nextLaunch = .regularApplication
    }

    /// Persist a second-pass cleanup for the next process, before either
    /// application runtime can open the store.
    public func scheduleStoreFamilyErasure(
        storeURL: URL,
        storageRootURL: URL,
    ) throws {
        var pendingErasures = try pendingStoreErasures()
        pendingErasures.insert(PendingStoreErasure(
            storeURL: storeURL.standardizedFileURL,
            storageRootURL: storageRootURL.standardizedFileURL,
        ))
        try persist(pendingErasures)
        pendingStoreErasureError = nil
    }

    /// Finish scheduled cleanup synchronously at process boot.
    ///
    /// Requests stay latched after a failure, and the error remains observable
    /// to Inspector. Returning `false` lets the host choose Inspector instead of
    /// starting a regular runtime against a store that may still be unreadable.
    @discardableResult
    public func completePendingStoreErasures(fileManager: FileManager) -> Bool {
        let pendingErasures: Set<PendingStoreErasure>
        do {
            pendingErasures = try pendingStoreErasures()
        } catch {
            pendingStoreErasureError = error.localizedDescription
            return false
        }

        var failedErasures: Set<PendingStoreErasure> = []
        var failureDescriptions: [String] = []
        for pendingErasure in pendingErasures {
            do {
                let family = InspectorSwiftDataStoreFamily(
                    storeURL: pendingErasure.storeURL,
                    storageRootURL: pendingErasure.storageRootURL,
                )
                try family.erase(using: fileManager)
            } catch {
                failedErasures.insert(pendingErasure)
                failureDescriptions.append(error.localizedDescription)
            }
        }

        do {
            try persist(failedErasures)
        } catch {
            failureDescriptions.append(error.localizedDescription)
        }
        pendingStoreErasureError = failureDescriptions.isEmpty
            ? nil
            : failureDescriptions.joined(separator: "\n")
        return failureDescriptions.isEmpty
    }

    private func pendingStoreErasures() throws -> Set<PendingStoreErasure> {
        guard let data = userDefaults.data(forKey: Self.pendingStoreErasuresKey) else {
            return []
        }
        return try JSONDecoder().decode(Set<PendingStoreErasure>.self, from: data)
    }

    private func persist(_ pendingErasures: Set<PendingStoreErasure>) throws {
        guard pendingErasures.isEmpty == false else {
            userDefaults.removeObject(forKey: Self.pendingStoreErasuresKey)
            return
        }
        try userDefaults.set(
            JSONEncoder().encode(pendingErasures),
            forKey: Self.pendingStoreErasuresKey,
        )
    }
}
