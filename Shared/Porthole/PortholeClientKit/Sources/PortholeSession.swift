import Foundation
import PortholeCore

/// A live, authenticated session with one device app. Send requests
/// (`manifest`, `invoke`, `query`, `subscribe`); a background read loop matches
/// responses to requests by id and routes unsolicited events into the
/// subscription streams it vends.
public actor PortholeSession {
    private let transport: any PortholeTransport
    private var pending: [UInt64: CheckedContinuation<PortholeResponse, Error>] = [:]
    private var subscriptions: [UInt64: AsyncThrowingStream<PortholeValue, Error>.Continuation] =
        [:]
    private var nextRequestID: UInt64 = 1
    private var readTask: Task<Void, Never>?
    private var isClosed = false

    /// The device's hello reply, available after `start()` completes the
    /// protocol handshake.
    public private(set) var deviceInfo: HelloReply?

    init(transport: some PortholeTransport) {
        self.transport = transport
    }

    /// Starts the read loop and performs the app-level hello (verifying protocol
    /// compatibility). Call once, before any request.
    func start(clientName: String) async throws {
        readTask = Task { await self.readLoop() }
        let response = try await request(.hello(HelloRequest(clientName: clientName)))
        guard case let .helloReply(reply) = response else {
            throw PortholeClientError.unexpectedResponse
        }
        guard reply.protocolVersion == portholeProtocolVersion else {
            throw PortholeError.protocolMismatch(
                theirs: reply.protocolVersion,
                ours: portholeProtocolVersion,
            )
        }
        deviceInfo = reply
    }

    public func manifest() async throws -> [ConnectorManifest] {
        let response = try await request(.listConnectors)
        guard case let .connectors(manifests) = response
        else { throw PortholeClientError.unexpectedResponse }
        return manifests
    }

    public func invoke(
        _ ref: PortholeActionRef,
        parameters: PortholeValue,
    ) async throws -> PortholeValue {
        let response = try await request(.invokeAction(ref: ref, parameters: parameters))
        guard case let .actionResult(value) = response
        else { throw PortholeClientError.unexpectedResponse }
        return value
    }

    public func query(
        _ ref: PortholeDataSourceRef,
        _ query: PortholeQuery,
    ) async throws -> PortholePage {
        let response = try await request(.query(ref: ref, query: query))
        guard case let .queryResult(page) = response
        else { throw PortholeClientError.unexpectedResponse }
        return page
    }

    /// Subscribes to a data source's live stream. Finishing/cancelling the
    /// returned stream unsubscribes on the device.
    public func subscribe(_ ref: PortholeDataSourceRef) async throws
        -> AsyncThrowingStream<PortholeValue, Error>
    {
        let response = try await request(.subscribe(ref: ref))
        guard case let .subscribed(subscriptionID) = response
        else { throw PortholeClientError.unexpectedResponse }
        let (stream, continuation) = AsyncThrowingStream<PortholeValue, Error>.makeStream()
        subscriptions[subscriptionID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(subscriptionID) }
        }
        return stream
    }

    private func unsubscribe(_ subscriptionID: UInt64) async {
        guard subscriptions.removeValue(forKey: subscriptionID) != nil, !isClosed else { return }
        _ = try? await request(.unsubscribe(subscriptionID: subscriptionID))
    }

    public func close() async {
        isClosed = true
        readTask?.cancel()
        await transport.close()
        for (_, continuation) in subscriptions {
            continuation.finish()
        }
        subscriptions.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: PortholeClientError.connectionClosed)
        }
        pending.removeAll()
    }

    private func request(_ request: PortholeRequest) async throws -> PortholeResponse {
        let id = nextRequestID
        nextRequestID += 1
        let response: PortholeResponse = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    let frame = try JSONEncoder().encode(PortholeRequestEnvelope(
                        id: id,
                        request: request,
                    ))
                    try await transport.send(frame)
                } catch {
                    resumePending(id, throwing: error)
                }
            }
        }
        if case let .failure(error) = response { throw error }
        return response
    }

    private func resumePending(_ id: UInt64, throwing error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func readLoop() async {
        do {
            for try await frame in transport.incoming {
                let envelope = try JSONDecoder().decode(PortholeResponseEnvelope.self, from: frame)
                if let id = envelope.requestID {
                    pending.removeValue(forKey: id)?.resume(returning: envelope.response)
                } else if case let .event(subscriptionID, value) = envelope.response {
                    subscriptions[subscriptionID]?.yield(value)
                }
            }
        } catch {
            failAll(with: error)
            return
        }
        failAll(with: PortholeClientError.connectionClosed)
    }

    private func failAll(with error: Error) {
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        for (_, continuation) in subscriptions {
            continuation.finish(throwing: error)
        }
        subscriptions.removeAll()
    }
}
