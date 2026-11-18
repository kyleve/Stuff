import WhereCore

/// Process startup ownership is separate from the persisted onboarding preference.
/// Only an opening state owns assembly work; only a running state owns a session.
@MainActor
enum WhereStartupState {
    case preparing(any WhereScopeAssembling)
    case opening(Opening)
    case open(WhereScope)
    case running(WhereSession)
    case retiring(Task<Void, Never>)
    case locked

    final class Opening {
        let bootstrap: any WhereScopeAssembling
        let task: Task<WhereScope, any Error>

        init(bootstrap: any WhereScopeAssembling, task: Task<WhereScope, any Error>) {
            self.bootstrap = bootstrap
            self.task = task
        }
    }

    var scope: WhereScope? {
        switch self {
            case let .open(scope): scope
            case let .running(session): session.scope
            case .preparing, .opening, .retiring, .locked: nil
        }
    }

    var session: WhereSession? {
        if case let .running(session) = self { session } else { nil }
    }

    var bootstrap: (any WhereScopeAssembling)? {
        switch self {
            case let .preparing(bootstrap): bootstrap
            case let .opening(opening): opening.bootstrap
            case .open, .running, .retiring, .locked: nil
        }
    }

    /// Stale assembly must finish and be discarded before another store can open.
    func shutdown() async {
        switch self {
            case let .preparing(bootstrap):
                await bootstrap.shutdown()
            case let .opening(opening):
                opening.task.cancel()
                await opening.bootstrap.shutdown()
                do {
                    let scope = try await opening.task.value
                    await scope.shutdown()
                } catch is CancellationError {
                    // The canceled assembly produced no scope to release.
                } catch {
                    WhereLog.root(WhereLaunchLog.self).servicesAssemblyFailed(error: .restricted(
                        .errorDetails,
                        error,
                    ))
                }
            case let .open(scope):
                await scope.shutdown()
            case let .running(session):
                await session.shutdown()
            case let .retiring(task):
                await task.value
            case .locked:
                break
        }
    }
}
