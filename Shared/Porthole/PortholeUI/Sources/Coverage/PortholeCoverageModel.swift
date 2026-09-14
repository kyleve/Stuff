import Foundation
import Observation
import PortholeCore

/// Loads one bounded page through the same read capabilities used by scripts and remote clients.
@MainActor @Observable
final class PortholeCoverageModel {
    struct Request: Equatable {
        let module: PortholeModuleID?
        let search: String
        let offset: Int
        var listsModules: Bool {
            module == nil && search.isEmpty
        }
    }

    enum Page {
        case modules(PortholeCoverageModulePage)
        case declarations(PortholeCoveragePage)

        var total: Int {
            switch self {
                case let .modules(page): page.total
                case let .declarations(page): page.total
            }
        }

        var count: Int {
            switch self {
                case let .modules(page): page.items.count
                case let .declarations(page): page.items.count
            }
        }
    }

    enum State {
        case idle, loading, loaded(Page), failed(String)
    }

    let scope: PortholeScopeToken
    let module: PortholeModuleID?
    let pageSize = 50
    var search = "" {
        didSet {
            guard oldValue != search else { return }
            offset = 0
            invalidateRequest()
        }
    }

    private(set) var offset = 0
    private(set) var state: State = .idle
    @ObservationIgnored private let client: PortholeCoverageClient
    @ObservationIgnored private var operationID: UUID?

    init(
        scope: PortholeScopeToken,
        module: PortholeModuleID?,
        execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue,
    ) {
        self.scope = scope
        self.module = module
        client = PortholeCoverageClient(execute: execute)
    }

    var request: Request {
        .init(module: module, search: search, offset: offset)
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await load()
    }

    func load() async {
        let request = request
        let operationID = UUID()
        self.operationID = operationID
        state = .loading
        do {
            let page: Page = if request.listsModules {
                try await .modules(client.modules(
                    in: scope,
                    offset: request.offset,
                    limit: pageSize,
                ))
            } else {
                try await .declarations(client.declarations(
                    in: scope,
                    query: .init(
                        module: request.module,
                        search: request.search,
                        status: .all,
                        offset: request.offset,
                        limit: pageSize,
                    ),
                ))
            }
            try Task.checkCancellation()
            guard self.operationID == operationID, self.request == request else { return }
            state = .loaded(page)
        } catch is CancellationError {
            if self.operationID == operationID { state = .idle }
        } catch {
            guard self.operationID == operationID, self.request == request else { return }
            PortholeUILog.failures
                .error("Coverage read failed: \(String(describing: error), privacy: .private)")
            state = .failed(error.localizedDescription)
        }
    }

    func previousPage() {
        guard case .loaded = state, offset > 0 else { return }
        offset = max(0, offset - pageSize)
        invalidateRequest()
    }

    func nextPage() {
        guard case let .loaded(page) = state, page.count > 0,
              offset < page.total, page.count < page.total - offset else { return }
        offset += page.count
        invalidateRequest()
    }

    func cancel() {
        operationID = nil
        if case .loading = state { state = .idle }
    }

    private func invalidateRequest() {
        operationID = nil
        state = .idle
    }
}
