import Foundation
import PeriscopeCore

/// Owns hourly foreground throttling and validated cache persistence.
@MainActor
public final class UpdateService {
    public struct Snapshot: Equatable {
        public let checkedAt: Date
        public let availability: UpdateCatalog.Availability
        public let browser: UpdateBuildBrowser
    }

    public let installed: InstalledBuild
    private let preferences: any UpdatePreferencesStoring
    private let client: any UpdateFetching
    private let now: () -> Date
    private var refreshSequence: UInt64 = 0
    /// Foreground checks reuse a successful result for one hour. Manual checks always fetch.
    private static let refreshInterval: TimeInterval = 3600
    private static let logger = Log<UpdateLog>(system: .shared)

    public init(
        installed: InstalledBuild,
        preferences: any UpdatePreferencesStoring,
        client: any UpdateFetching,
        now: @escaping () -> Date,
    ) {
        self.installed = installed
        self.preferences = preferences
        self.client = client
        self.now = now
    }

    public var cached: Snapshot? {
        guard let cached = preferences.installerUpdates.cached,
              cached.feedURL == installed.feedURL else { return nil }
        do {
            try cached.catalog.validate(feedURL: installed.feedURL)
        } catch {
            Self.logger.cacheRejected(error: .restricted(.errorDetails, error))
            preferences.installerUpdates = UpdatePreferences(cached: nil)
            return nil
        }
        return Snapshot(
            checkedAt: cached.checkedAt,
            availability: cached.catalog.availability(for: installed),
            browser: UpdateBuildBrowser(catalog: cached.catalog, installed: installed),
        )
    }

    /// The cached result an automatic check may reuse without superseding a network request.
    public var cachedForAutomaticRefresh: Snapshot? {
        guard let cached,
              (0 ..< Self.refreshInterval).contains(now().timeIntervalSince(cached.checkedAt))
        else { return nil }
        return cached
    }

    public func refresh(force: Bool) async throws -> Snapshot {
        try Task.checkCancellation()
        if !force, let cachedForAutomaticRefresh { return cachedForAutomaticRefresh }
        refreshSequence += 1
        let sequence = refreshSequence
        do {
            let catalog = try await Self.logger.measure(.fetch, budget: .seconds(15)) {
                try await client.fetch(from: installed.feedURL)
            }
            try Task.checkCancellation()
            guard sequence == refreshSequence else { throw CancellationError() }
            try catalog.validate(feedURL: installed.feedURL)
            let checkedAt = now()
            var registration = preferences.installerUpdates
            registration.cached = .init(
                feedURL: installed.feedURL,
                checkedAt: checkedAt,
                catalog: catalog,
            )
            preferences.installerUpdates = registration
            return Snapshot(
                checkedAt: checkedAt,
                availability: catalog.availability(for: installed),
                browser: UpdateBuildBrowser(catalog: catalog, installed: installed),
            )
        } catch {
            guard !Task.isCancelled, sequence == refreshSequence,
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled
            else {
                throw CancellationError()
            }
            Self.logger.checkFailed(error: .restricted(.errorDetails, error))
            throw error
        }
    }
}
