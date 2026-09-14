import Foundation
import Network
import PortholeCore

/// An exchange never retries a request after an uncertain transport failure.
public protocol PortholeRemoteTransport: Sendable {
    func exchange(_ request: Data) async throws -> Data
    func close() async
}

actor PortholeTLSTransport: PortholeRemoteTransport {
    private let channel: PortholeConnection
    private var exchanging = false

    init(channel: PortholeConnection) {
        self.channel = channel
    }

    func exchange(_ request: Data) async throws -> Data {
        guard !exchanging else { throw PortholeRemoteError.connectionBusy }
        exchanging = true
        defer { exchanging = false }
        do {
            try await channel.send(request)
            return try await channel.receive()
        } catch {
            channel.cancel()
            throw error
        }
    }

    func close() {
        channel.cancel()
    }
}

/// Remote clients use the same capability and invocation values as the on-device controls.
public struct PortholeRemoteClient: PortholeExecuting {
    private let session: PortholeRemoteClientSession

    public init(transport: any PortholeRemoteTransport) {
        session = PortholeRemoteClientSession(transport: transport)
    }

    public static func connect(
        endpoint: NWEndpoint,
        identity: PortholeTLSIdentity,
        serverPin: Data,
    ) async throws -> Self {
        let parameters = try PortholeTLS.client(identity: identity, serverPin: serverPin)
        let channel = PortholeConnection(NWConnection(to: endpoint, using: parameters))
        try await channel.start()
        return Self(transport: PortholeTLSTransport(channel: channel))
    }

    public func close() async {
        await session.close()
    }

    public func application() async throws -> PortholeRemoteApplication {
        guard case let .application(application) = try await exchange(.application)
        else { throw PortholeRemoteError.invalidMessage }
        return application
    }

    public func capabilities(in scope: PortholeScopeToken) async throws -> [PortholeCapability] {
        var items: [PortholeCapability] = []
        var expectedTotal: Int?
        var seen: Set<PortholeSymbolID> = []
        repeat {
            let page = try await capabilityPage(in: scope, offset: items.count, limit: 200)
            guard expectedTotal == nil || expectedTotal == page.total
            else {
                throw PortholeRemoteError
                    .remoteFailure("The capability catalog changed. Reload this scope.")
            }
            expectedTotal = page.total
            for item in page.items {
                guard seen.insert(item.id).inserted
                else { throw PortholeRemoteError.invalidMessage }
                items.append(item)
            }
        } while items.count < (expectedTotal ?? 0)
        return items
    }

    public func capabilityPage(
        in scope: PortholeScopeToken,
        offset: Int,
        limit: Int,
    ) async throws -> PortholeCapabilityPage {
        guard offset >= 0,
              (1 ... 200).contains(limit) else { throw PortholeRemoteError.invalidMessage }
        guard case let .capabilities(page) = try await exchange(.capabilities(
            scope: scope,
            offset: offset,
            limit: limit,
        )),
            page.offset == offset, page.total >= 0, page.total <= 1_000_000,
            page.items.count <= limit, page.items.count <= max(0, page.total - offset),
            offset >= page.total || !page.items.isEmpty
        else { throw PortholeRemoteError.invalidMessage }
        return page
    }

    public func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        guard case let .value(value) = try await exchange(.invoke(invocation))
        else { throw PortholeRemoteError.invalidMessage }
        return value
    }

    /// The runtime owns sampling; delivery retains only the latest unread sample.
    public func observations(
        of invocation: PortholeInvocation,
        interval: Duration,
    ) -> AsyncThrowingStream<PortholeValue, any Error> {
        session.observations(client: self, invocation: invocation, interval: interval)
    }

    private func exchange(_ operation: PortholeRemoteRequest
        .Operation) async throws -> PortholeRemoteResponse.Result
    {
        let request = PortholeRemoteRequest(requestID: UUID(), operation: operation)
        let bytes = try await session.exchange(JSONEncoder().encode(request))
        guard bytes.count <= PortholeRemoteFraming.maximumBytes
        else { throw PortholeRemoteError.frameTooLarge }
        let response = try JSONDecoder().decode(PortholeRemoteResponse.self, from: bytes)
        guard response.version == 1,
              response.requestID == request.requestID
        else { throw PortholeRemoteError.invalidMessage }
        switch response.result {
            case let .approvalRequired(proposal): throw PortholeError.approvalRequired(proposal)
            case let .failure(code, message):
                if code == "stale_scope" { throw PortholeError.staleScope }
                throw PortholeRemoteError.remoteFailure(message)
            case .application, .capabilities, .value: return response.result
        }
    }
}
