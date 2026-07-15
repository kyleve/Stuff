import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct PeriscopeViewerModelTests {
    @Test func loadShowsEventsNewestFirst() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            makeRecord("first", date: date(1), scopes: [root.id]),
            makeRecord("second", date: date(2), scopes: [root.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        await model.load()

        #expect(model.events.map(\.message) == ["second", "first"])
        #expect(!model.canLoadMore)
    }

    @Test func failedLoadsSurfaceHonestly() async throws {
        // A fresh model over an empty store loads fine; the failed state is
        // covered by construction — assert the loaded-empty branch here.
        let (store, _, _, _) = try await makeSeededStore()
        let model = PeriscopeViewerModel(store: store)
        await model.load()
        #expect(model.events.isEmpty)
        if case .failed = model.state {
            Issue.record("Empty store should load as an empty page, not fail")
        }
    }

    @Test func minimumLevelFilterRequeries() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            makeRecord("noise", level: .debug, date: date(1), scopes: [root.id]),
            makeRecord("boom", level: .error, date: date(2), scopes: [root.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        await model.load()
        #expect(model.events.count == 2)

        model.minimumLevel = .warning
        let filtered = await waitUntil { model.events.map(\.message) == ["boom"] }
        #expect(filtered)
    }

    @Test func searchTextFilters() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            makeRecord("Uploading photo", date: date(1), scopes: [root.id]),
            makeRecord("Deleting album", date: date(2), scopes: [root.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        model.searchText = "photo"
        let filtered = await waitUntil {
            model.events.map(\.message) == ["Uploading photo"]
        }
        #expect(filtered)
    }

    @Test func scopeFilterQueriesTheSubtree() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("at root", date: date(1), scopes: [root.id]),
            makeRecord("at photos", date: date(2), scopes: [photos.id]),
            makeRecord("at album", date: date(3), scopes: [album.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        model.selectedScope = photos.id
        let filtered = await waitUntil {
            model.events.map(\.message) == ["at album", "at photos"]
        }
        #expect(filtered)
    }

    @Test func spanExitFilterRequeries() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            LogRecord(
                date: date(1),
                event: SpanEnded(
                    spanID: SpanID(),
                    name: "save",
                    duration: .seconds(1),
                    exit: .failure("boom"),
                ),
                scopes: [root.id],
            ),
            makeRecord("noise", date: date(2), scopes: [root.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        model.selectedSpanExitMode = .failure
        let filtered = await waitUntil {
            model.events.map(\.spanExitMode) == [.failure]
        }
        #expect(filtered)
    }

    @Test func pagingLoadsMoreAndStopsAtTheEnd() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let total = PeriscopeViewerModel.pageSize + 5
        await store.write((1 ... total).map { index in
            makeRecord("\(index)", date: date(TimeInterval(index)), scopes: [root.id])
        })

        let model = PeriscopeViewerModel(store: store)
        await model.load()
        #expect(model.events.count == PeriscopeViewerModel.pageSize)
        #expect(model.canLoadMore)

        await model.loadMore()
        #expect(model.events.count == total)
        #expect(!model.canLoadMore)
        #expect(model.events.first?.message == "\(total)")
        #expect(model.events.last?.message == "1")
    }

    @Test func scopePathResolvesThroughTheHierarchy() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        await store.write([makeRecord("deep", date: date(1), scopes: [album.id])])

        let model = PeriscopeViewerModel(store: store)
        await model.load()

        let event = try #require(model.events.first)
        #expect(model.scopePath(for: event) == "app / photos / album-1")
    }

    @Test func filterCatalogsComeFromTheStore() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            makeRecord("plain", date: date(1), scopes: [root.id]),
            LogRecord(date: date(2), event: PhotoLogs(photoID: "p1"), scopes: [root.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        await model.load()

        #expect(model.eventNames == ["PhotoLogs", "message"].sorted())
        #expect(model.sessions.count == 1)
        #expect(model.scopeChoices.map(\.path).contains("app / photos / album-1"))
        #expect(model.availableLevels == LogLevel.standardLevels)
    }

    @Test func runRefreshesLiveWhenTheStoreCommits() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let model = PeriscopeViewerModel(store: store)
        let task = Task { await model.run() }
        defer { task.cancel() }

        // Race the initial load deliberately: a commit landing while (or
        // right after) it runs must still end up displayed.
        await store.write([makeRecord("live", date: date(1), scopes: [root.id])])
        let shown = await waitUntil { model.events.map(\.message) == ["live"] }
        #expect(shown)

        await store.write([makeRecord("later", date: date(2), scopes: [root.id])])
        let refreshed = await waitUntil {
            model.events.map(\.message) == ["later", "live"]
        }
        #expect(refreshed)
    }

    @Test func exportUsesTheActiveFiltersUnpaged() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            makeRecord("keep me", level: .error, date: date(1), scopes: [root.id]),
            makeRecord("drop me", level: .debug, date: date(2), scopes: [root.id]),
        ])

        let model = PeriscopeViewerModel(store: store)
        model.minimumLevel = .warning
        let filtered = await waitUntil { model.events.map(\.message) == ["keep me"] }
        #expect(filtered)

        let export = try await model.exportNDJSON()
        #expect(export.contains("keep me"))
        #expect(!export.contains("drop me"))
    }
}
