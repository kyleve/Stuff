import Foundation
import PortholeCore

/// One authorization boundary serves local, remote, manual, and AI clients.
public struct PortholeRemoteDispatcher: Sendable {
    private let executor: any PortholeExecuting
    private let application: @Sendable () async throws -> PortholeRemoteApplication

    public init(
        executor: any PortholeExecuting,
        application: @escaping @Sendable () async throws -> PortholeRemoteApplication,
    ) {
        self.executor = executor
        self.application = application
    }

    func makeSession() -> PortholeRemoteSession {
        PortholeRemoteSession(dispatcher: self, executor: executor)
    }

    public func respond(to request: PortholeRemoteRequest) async -> PortholeRemoteResponse {
        let result: PortholeRemoteResponse.Result
        do {
            guard request.version == 1 else { throw PortholeRemoteError.invalidMessage }
            switch request.operation {
                case .application: result = try await .application(application())
                case let .capabilities(scope, offset, limit):
                    guard offset >= 0,
                          (1 ... 200).contains(limit)
                    else { throw PortholeRemoteError.invalidMessage }
                    let catalog = try await executor.capabilities(in: scope)
                    result = .capabilities(.init(
                        offset: offset,
                        total: catalog.count,
                        items: Array(catalog.dropFirst(offset).prefix(limit)),
                    ))
                case let .invoke(invocation): result = try await .value(executor.invoke(invocation))
            }
        } catch let PortholeError.approvalRequired(proposal) {
            result = .approvalRequired(proposal)
        } catch PortholeError.staleScope {
            result = .failure(
                code: "stale_scope",
                message: "The application scope has ended. Select a current scope.",
            )
        } catch is CancellationError {
            result = .failure(
                code: "cancelled",
                message: "The request was cancelled. A started operation may have completed.",
            )
        } catch {
            result = .failure(code: "operation_failed", message: error.localizedDescription)
        }
        return PortholeRemoteResponse(requestID: request.requestID, result: result)
    }
}
