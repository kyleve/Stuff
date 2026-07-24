import Foundation
import PortholeCore
@testable import PortholeKit

struct TestTimeoutError: Error {}

func withTimeout<T: Sendable>(
    _ duration: Duration = .seconds(2),
    _ operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TestTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// A minimal in-process client for exercising a `PortholeSessionRouter` over a
/// loopback transport: it matches responses to requests by id and funnels
/// unsolicited events into a stream. (The real client is `PortholeClientKit`;
/// this is just enough to drive the runtime's tests.)
actor TestSessionClient {
    enum Failure: Error { case connectionClosed }

    private let transport: any PortholeTransport
    private var pending: [UInt64: CheckedContinuation<PortholeResponse, Error>] = [:]
    private var nextID: UInt64 = 1
    private var readTask: Task<Void, Never>?

    let events: AsyncStream<PortholeResponseEnvelope>
    private let eventsContinuation: AsyncStream<PortholeResponseEnvelope>.Continuation

    init(transport: some PortholeTransport) {
        self.transport = transport
        (events, eventsContinuation) = AsyncStream.makeStream()
    }

    func start() {
        readTask = Task { await self.readLoop() }
    }

    private func readLoop() async {
        do {
            for try await frame in transport.incoming {
                let envelope = try JSONDecoder().decode(PortholeResponseEnvelope.self, from: frame)
                if let id = envelope.requestID {
                    pending.removeValue(forKey: id)?.resume(returning: envelope.response)
                } else {
                    eventsContinuation.yield(envelope)
                }
            }
        } catch {}
        for (_, continuation) in pending {
            continuation.resume(throwing: Failure.connectionClosed)
        }
        pending.removeAll()
        eventsContinuation.finish()
    }

    func send(_ request: PortholeRequest) async throws -> PortholeResponse {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    let frame = try JSONEncoder().encode(PortholeRequestEnvelope(
                        id: id,
                        request: request,
                    ))
                    try await transport.send(frame)
                } catch {
                    self.fail(id: id, with: error)
                }
            }
        }
    }

    private func fail(id: UInt64, with error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    /// Reads the next `count` event payloads (subscription id + value).
    func nextEvents(_ count: Int) async throws -> [(UInt64, PortholeValue)] {
        try await withTimeout {
            var collected: [(UInt64, PortholeValue)] = []
            for await envelope in self.events {
                if case let .event(subscriptionID, value) = envelope.response {
                    collected.append((subscriptionID, value))
                    if collected.count == count { break }
                }
            }
            return collected
        }
    }
}

/// A connector fixture exercising the router's dispatch, validation, error, and
/// subscription paths.
final class TestEchoConnector: PortholeConnector {
    let descriptor = PortholeConnectorDescriptor(
        id: "test",
        title: "Test",
        summary: "Fixture connector.",
        version: 1,
    )

    func actions() -> [PortholeAction] {
        [
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "echo",
                    title: "Echo",
                    summary: "Echoes the given integer.",
                    parameters: .object(
                        ["value": .integer("A value to echo")],
                        required: ["value"],
                    ),
                    isDestructive: false,
                ),
                handler: { parameters in
                    .object(["echoed": parameters["value"] ?? .null])
                },
            ),
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "boom",
                    title: "Boom",
                    summary: "Always throws.",
                    parameters: .object([:]),
                    isDestructive: false,
                ),
                handler: { _ in throw TestConnectorError.boom },
            ),
        ]
    }

    func dataSources() -> [PortholeDataSource] {
        [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "numbers",
                    title: "Numbers",
                    summary: "Returns count rows.",
                    rowSchema: .object(["n": .integer()]),
                    filters: .object(["count": .integer()]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    let count = Int(query.filters["count"]?.intValue ?? 0)
                    let rows = (0 ..< count).map { PortholeValue.object(["n": .int(Int64($0))]) }
                    return PortholePage(rows: rows, nextCursor: nil, totalCount: count)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "ticks",
                    title: "Ticks",
                    summary: "Emits an incrementing counter.",
                    rowSchema: .object(["tick": .integer()]),
                    filters: .object([:]),
                    supportsSubscription: true,
                ),
                fetch: { _ in PortholePage(rows: [], nextCursor: nil) },
                subscribe: {
                    AsyncStream { continuation in
                        let task = Task {
                            var tick = 0
                            while !Task.isCancelled {
                                continuation.yield(.object(["tick": .int(Int64(tick))]))
                                tick += 1
                                try? await Task.sleep(for: .milliseconds(2))
                            }
                            continuation.finish()
                        }
                        continuation.onTermination = { _ in task.cancel() }
                    }
                },
            ),
        ]
    }
}

enum TestConnectorError: Error { case boom }
