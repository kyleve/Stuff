import Foundation
import PortholeCore
import PortholeRemote
@testable import PortholeUI

enum PortholeRemoteUITestSupport {
    static let scope = PortholeScopeToken(id: .init(rawValue: "fixture"), generation: UUID())
    static func server() throws -> PortholePairedServer {
        let value = PortholeValue.object([
            "id": .string(UUID().uuidString),
            "serviceName": .string("Fixture"),
            "certificatePin": .string(Data(repeating: 1, count: 32).base64EncodedString()),
        ])
        return try JSONDecoder().decode(
            PortholePairedServer.self,
            from: JSONEncoder().encode(value),
        )
    }

    static func capability() -> PortholeCapability {
        .init(
            id: .init(rawValue: "fixture.change"),
            module: .init(rawValue: "Fixture"),
            name: "Change",
            summary: "Change a fixture",
            parameters: [.init(
                name: "value",
                summary: "New value",
                schema: .string,
                required: true,
            )],
            result: .string,
            effect: .mutation,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
    }
}

actor PortholeRemoteUITransport: PortholeRemoteTransport {
    private(set) var closed = false
    func exchange(_ data: Data) throws -> Data {
        let request = try JSONDecoder().decode(PortholeRemoteRequest.self, from: data)
        let result: PortholeRemoteResponse.Result = switch request.operation {
            case .application: .application(.init(
                    applicationID: UUID(),
                    name: "Fixture",
                    scopes: [PortholeRemoteUITestSupport.scope],
                ))
            case let .capabilities(_, offset, _): .capabilities(.init(
                    offset: offset,
                    total: 1,
                    items: [PortholeRemoteUITestSupport.capability()],
                ))
            case .invoke: .value(.string("done"))
        }
        return try JSONEncoder().encode(PortholeRemoteResponse(
            requestID: request.requestID,
            result: result,
        ))
    }

    func close() {
        closed = true
    }
}

actor PortholeRemoteUIConnector: PortholeRemoteConnecting {
    nonisolated func discoveredApplications()
        -> AsyncThrowingStream<[PortholeDiscoveredApplication], any Error>
    {
        AsyncThrowingStream { $0.yield([]); $0.finish() }
    }

    let transport: PortholeRemoteUITransport
    let servers: [PortholePairedServer]
    private var waiter: CheckedContinuation<Void, Never>?
    private var arrived: CheckedContinuation<Void, Never>?
    private var holdConnection = false
    private var started = false
    init(transport: PortholeRemoteUITransport, servers: [PortholePairedServer]) {
        self.transport = transport; self.servers = servers
    }

    func pairedServers() -> [PortholePairedServer] {
        servers
    }

    func enroll(
        invitation _: PortholeEnrollmentInvitation,
        clientName _: String,
    ) throws -> PortholePairedServer {
        throw PortholeRemoteError
            .invalidEnrollment
    }

    func hold() {
        holdConnection = true
    }

    func connect(server _: PortholePairedServer) async -> PortholeRemoteClient {
        started = true
        arrived?.resume(); arrived = nil
        if holdConnection { await withCheckedContinuation { waiter = $0 } }
        return PortholeRemoteClient(transport: transport)
    }

    func waitForArrival() async {
        if started { return }
        await withCheckedContinuation { arrived = $0 }
    }

    func release() {
        holdConnection = false; waiter?.resume(); waiter = nil
    }
}
