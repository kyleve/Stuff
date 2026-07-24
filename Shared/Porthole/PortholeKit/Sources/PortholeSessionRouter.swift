import Foundation
import PortholeCore

/// Serves one authenticated connection: it decodes request envelopes from the
/// transport, validates action/query parameters against the connector schemas,
/// dispatches to the resolved handlers, and streams subscription events back.
///
/// An `actor` so its subscription table is race-free; request handling is
/// serialized per connection, but actor reentrancy lets subscription-event sends
/// interleave at the `await` in a slow handler.
actor PortholeSessionRouter {
    private let transport: any PortholeTransport
    private let connectors: ResolvedConnectors
    private let hello: HelloReply
    private let connectorIDs: Set<PortholeConnectorID>

    private var subscriptions: [UInt64: SubscriptionTasks] = [:]
    private var nextSubscriptionID: UInt64 = 1

    private struct SubscriptionTasks {
        var feeder: Task<Void, Never>
        var pump: Task<Void, Never>
    }

    /// Bounds per-subscription buffering so a fast producer can't grow memory
    /// without limit; the oldest queued events are dropped when full.
    private static let subscriptionBufferSize = 256

    init(transport: some PortholeTransport, connectors: ResolvedConnectors, hello: HelloReply) {
        self.transport = transport
        self.connectors = connectors
        self.hello = hello
        connectorIDs = connectors.connectorIDs
    }

    /// Reads and services frames until the transport closes, then cancels any
    /// open subscriptions. Returns when the connection ends.
    func run() async {
        do {
            for try await frame in transport.incoming {
                await handle(frame)
            }
        } catch {
            PortholeLog.session
                .error("Session read failed: \(String(describing: error), privacy: .public)")
        }
        for (_, tasks) in subscriptions {
            tasks.feeder.cancel()
            tasks.pump.cancel()
        }
        subscriptions.removeAll()
    }

    private func handle(_ frame: Data) async {
        let envelope: PortholeRequestEnvelope
        do {
            envelope = try JSONDecoder().decode(PortholeRequestEnvelope.self, from: frame)
        } catch {
            PortholeLog.session
                .error(
                    "Dropping undecodable request frame: \(String(describing: error), privacy: .public)",
                )
            return
        }
        let response = await response(for: envelope.request)
        await send(PortholeResponseEnvelope(requestID: envelope.id, response: response))
    }

    private func response(for request: PortholeRequest) async -> PortholeResponse {
        switch request {
            case .hello:
                return .helloReply(hello)
            case .listConnectors:
                return .connectors(connectors.manifests)
            case .ping:
                return .pong
            case let .invokeAction(ref, parameters):
                return await invoke(ref, parameters: parameters)
            case let .query(ref, query):
                return await runQuery(ref, query: query)
            case let .subscribe(ref):
                return subscribe(ref)
            case let .unsubscribe(subscriptionID):
                cancelSubscription(subscriptionID)
                return .pong
        }
    }

    private func invoke(
        _ ref: PortholeActionRef,
        parameters: PortholeValue,
    ) async -> PortholeResponse {
        switch connectors.action(ref, hasConnector: connectorIDs.contains) {
            case let .failure(error):
                return .failure(error)
            case let .success(action):
                do {
                    try action.descriptor.parameters.validate(parameters)
                } catch let error as PortholeError {
                    return .failure(error)
                } catch {
                    return .failure(.invalidParameters(String(describing: error)))
                }
                do {
                    return try await .actionResult(action.handler(parameters))
                } catch let error as PortholeError {
                    return .failure(error)
                } catch {
                    return .failure(.handlerFailed(String(describing: error)))
                }
        }
    }

    private func runQuery(
        _ ref: PortholeDataSourceRef,
        query: PortholeQuery,
    ) async -> PortholeResponse {
        switch connectors.dataSource(ref, hasConnector: connectorIDs.contains) {
            case let .failure(error):
                return .failure(error)
            case let .success(source):
                do {
                    try source.descriptor.filters.validate(query.filters)
                } catch let error as PortholeError {
                    return .failure(error)
                } catch {
                    return .failure(.invalidParameters(String(describing: error)))
                }
                do {
                    return try await .queryResult(source.fetch(query))
                } catch let error as PortholeError {
                    return .failure(error)
                } catch {
                    return .failure(.handlerFailed(String(describing: error)))
                }
        }
    }

    private func subscribe(_ ref: PortholeDataSourceRef) -> PortholeResponse {
        switch connectors.dataSource(ref, hasConnector: connectorIDs.contains) {
            case let .failure(error):
                return .failure(error)
            case let .success(source):
                guard source.descriptor.supportsSubscription,
                      let makeStream = source.subscribe
                else {
                    return .failure(.subscriptionNotSupported(ref))
                }
                let subscriptionID = nextSubscriptionID
                nextSubscriptionID += 1
                start(subscriptionID: subscriptionID, makeStream: makeStream)
                return .subscribed(subscriptionID: subscriptionID)
        }
    }

    private func start(
        subscriptionID: UInt64,
        makeStream: @escaping @Sendable () -> AsyncStream<PortholeValue>,
    ) {
        let source = makeStream()
        // Re-buffer through a bounded stream so our memory ceiling holds
        // regardless of the connector's own buffering policy (drop-oldest).
        let (bounded, continuation) = AsyncStream.makeStream(
            of: PortholeValue.self,
            bufferingPolicy: .bufferingNewest(Self.subscriptionBufferSize),
        )
        let feeder = Task {
            for await value in source {
                if Task.isCancelled { break }
                continuation.yield(value)
            }
            continuation.finish()
        }
        let pump = Task { [weak self] in
            for await value in bounded {
                if Task.isCancelled { break }
                await self?.send(PortholeResponseEnvelope(
                    requestID: nil,
                    response: .event(subscriptionID: subscriptionID, value: value),
                ))
            }
        }
        subscriptions[subscriptionID] = SubscriptionTasks(feeder: feeder, pump: pump)
    }

    private func cancelSubscription(_ subscriptionID: UInt64) {
        guard let tasks = subscriptions.removeValue(forKey: subscriptionID) else { return }
        tasks.feeder.cancel()
        tasks.pump.cancel()
    }

    private func send(_ envelope: PortholeResponseEnvelope) async {
        do {
            let frame = try JSONEncoder().encode(envelope)
            try await transport.send(frame)
        } catch {
            PortholeLog.session
                .error("Failed to send response: \(String(describing: error), privacy: .public)")
        }
    }
}
