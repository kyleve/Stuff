import Foundation
import InstallerKit
@_spi(Testing) @testable import InstallerKitUI
import TestHostSupport
import Testing
import UIKit

/// Holds a manual refresh across the page's checking-state redraw.
@MainActor
struct UpdatePageRefreshFixture {
    let client = UpdatePageClient(catalog: InstallerPreview.catalog(.available))
    let clock = UpdatePageClock()
    let model: UpdateModel

    init() {
        let clock = clock
        model = UpdateModel(service: UpdateService(
            installed: InstallerPreview.distribution(),
            preferences: UpdatePagePreferences(),
            client: client,
            now: { clock.date },
        ))
    }

    func checkRefresh(in host: UIViewController) async throws {
        try await waitForUpdatePage { model.needsAttention && !model.isChecking }
        let control = try #require(refreshControl(in: host.view))
        defer {
            client.pending?.resume(throwing: CancellationError())
            client.pending = nil
        }
        client.held = true
        clock.date += 1
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        try await waitForUpdatePage { client.pending != nil && model.isChecking }
        host.view.layoutIfNeeded()
        client.pending?.resume(returning: client.catalog)
        client.pending = nil
        try await waitForUpdatePage { !model.isChecking }
        #expect(!client.wasCancelled)
        #expect(model.state.snapshot?.checkedAt == clock.date)
    }

    private func refreshControl(in view: UIView) -> UIRefreshControl? {
        if let control = view as? UIRefreshControl { return control }
        return view.subviews.lazy.compactMap { refreshControl(in: $0) }.first
    }
}

@MainActor
func waitForUpdatePage(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
        guard ContinuousClock.now < deadline
        else { throw TestHostError("Update page did not settle") }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
final class UpdatePagePreferences: UpdatePreferencesStoring {
    var installerUpdates = UpdatePreferences(cached: nil)
}

@MainActor
final class UpdatePageClient: UpdateFetching {
    let catalog: UpdateCatalog
    private(set) var requests = 0
    var held = false
    var pending: CheckedContinuation<UpdateCatalog, any Error>?
    private(set) var wasCancelled = false

    init(catalog: UpdateCatalog) {
        self.catalog = catalog
    }

    func fetch(from _: URL) async throws -> UpdateCatalog {
        requests += 1
        if held {
            let value = try await withCheckedThrowingContinuation { pending = $0 }
            wasCancelled = Task.isCancelled
            return value
        }
        return catalog
    }
}

@MainActor
final class UpdatePageClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}
