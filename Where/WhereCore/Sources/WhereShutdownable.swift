/// Owns background work that must be retired before its data scope is released.
///
/// Shutdown is terminal and idempotent: cancel and join owned tasks, and never restart them.
/// It preserves user data, recording consent, and durable pending samples. Callers must stop
/// handing new work to a retired scope; this is not a per-API access-control boundary.
/// LocationSource.stop() instead suspends physical acquisition and permits a later start.
public protocol WhereShutdownable: Sendable {
    func shutdown() async
}
