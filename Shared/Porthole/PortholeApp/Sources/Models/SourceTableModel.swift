import Foundation
import PortholeClientKit
import PortholeCore

/// Loads and paginates one data source, and optionally tails it live.
@MainActor
@Observable
final class SourceTableModel {
    let descriptor: PortholeDataSourceDescriptor
    private let ref: PortholeDataSourceRef
    private let session: PortholeSession

    private(set) var rows: [PortholeValue] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var isLive = false {
        didSet {
            guard oldValue != isLive else { return }
            isLive ? startTail() : stopTail()
        }
    }

    private var tailTask: Task<Void, Never>?

    init(
        descriptor: PortholeDataSourceDescriptor,
        connector: PortholeConnectorID,
        session: PortholeSession,
    ) {
        self.descriptor = descriptor
        ref = PortholeDataSourceRef(connector: connector, source: descriptor.id)
        self.session = session
    }

    var columns: [String] {
        Rendering.columns(for: rows)
    }

    var canLoadMore: Bool {
        nextCursor != nil
    }

    func loadFirstPage() async {
        rows = []
        nextCursor = nil
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.query(ref, PortholeQuery(cursor: nextCursor))
            rows.append(contentsOf: page.rows)
            nextCursor = page.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func startTail() {
        tailTask = Task { [weak self, ref, session] in
            do {
                let stream = try await session.subscribe(ref)
                for try await value in stream {
                    self?.rows.append(value)
                }
            } catch {
                self?.errorMessage = String(describing: error)
            }
        }
    }

    private func stopTail() {
        tailTask?.cancel()
        tailTask = nil
    }

    /// Cancels any live tail; call when the view goes away.
    func teardown() {
        stopTail()
    }
}
