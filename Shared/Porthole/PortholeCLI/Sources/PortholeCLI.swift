import Darwin
import Foundation
import PortholeCore
import PortholeRemote

@main
enum PortholeCLI {
    static func main() async {
        do { try await run(PortholeCLICommand.parse(Array(CommandLine.arguments.dropFirst()))) }
        catch {
            FileHandle.standardError.write(Data("Porthole: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ command: PortholeCLICommand) async throws {
        let keychain = PortholeRemoteKeychain(service: "client", accessGroup: nil)
        switch command {
            case .help: print(PortholeCLICommand.usage)
            case .paired: try output(keychain.pairedServers())
            case .discover:
                for try await applications in PortholeDiscovery
                    .applications()
                {
                    try output(applications.map(\.name))
                }
            case .pair:
                FileHandle.standardError
                    .write(Data("Paste the invitation shown in the app, then press Return:\n".utf8))
                guard let line = readLine(),
                      line.utf8.count <= 8192 else { throw PortholeRemoteError.invalidEnrollment }
                let invitation = try PortholeEnrollmentInvitation.decode(line)
                let identity = try keychain.identity(
                    name: Host.current().localizedName ?? "Porthole CLI",
                    at: Date(),
                )
                let server = try await PortholeRemotePairing.enroll(
                    invitation: invitation,
                    identity: identity,
                    clientName: Host.current().localizedName ?? "Porthole CLI",
                )
                try keychain.save(server: server)
                try output(server)
            case let .application(server):
                let client = try await connect(server: server, keychain: keychain)
                do { try await output(client.application()); await client.close() }
                catch { await client.close(); throw error }
            case let .capabilities(server, file):
                let scope = try JSONDecoder().decode(
                    PortholeScopeToken.self,
                    from: input(file: file),
                )
                let client = try await connect(server: server, keychain: keychain)
                do { try await output(client.capabilities(in: scope)); await client.close() }
                catch { await client.close(); throw error }
            case let .invoke(server, file), let .watch(server, file):
                let invocation = try JSONDecoder().decode(
                    PortholeInvocation.self,
                    from: input(file: file),
                )
                let client = try await connect(server: server, keychain: keychain)
                do {
                    if case .watch = command {
                        for try await value in client.observations(
                            of: invocation,
                            interval: .seconds(1),
                        ) {
                            try output(value)
                        }
                    } else { try await output(client.invoke(invocation)) }
                    await client.close()
                } catch let PortholeError.approvalRequired(proposal) {
                    try output(proposal)
                    FileHandle.standardError
                        .write(
                            Data(
                                "Approval is required on the device. After approval, retry this exact invocation.\n"
                                    .utf8,
                            ),
                        )
                    await client.close()
                } catch { await client.close(); throw error }
            case let .mcp(server):
                let client = try await connect(server: server, keychain: keychain)
                let bridge = PortholeMCPServer(client: client)
                do {
                    while let line = readLine() {
                        guard line.utf8.count <= 4 * 1024 * 1024
                        else { throw PortholeRemoteError.frameTooLarge }
                        if let response = try await bridge.respond(to: Data(line.utf8)) {
                            FileHandle.standardOutput.write(response + Data([10]))
                        }
                    }
                    await client.close()
                } catch { await client.close(); throw error }
        }
    }

    private static func connect(
        server name: String,
        keychain: PortholeRemoteKeychain,
    ) async throws -> PortholeRemoteClient {
        let matches = try keychain.pairedServers().filter { $0.serviceName == name }
        guard matches.count == 1,
              let server = matches.first else { throw PortholeRemoteError.untrustedPeer }
        let identity = try keychain.identity(
            name: Host.current().localizedName ?? "Porthole CLI",
            at: Date(),
        )
        return try await PortholeRemoteClient.connect(
            endpoint: server.endpoint,
            identity: identity,
            serverPin: server.certificatePin,
        )
    }

    private static func input(file: String) throws -> Data {
        let data: Data = if file == "-" { try FileHandle.standardInput.readToEnd() ?? Data() }
        else { try Data(contentsOf: URL(fileURLWithPath: file), options: .mappedIfSafe) }
        guard data.count <= 4 * 1024 * 1024 else { throw PortholeRemoteError.frameTooLarge }
        return data
    }

    private static func output(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileHandle.standardOutput.write(encoder.encode(value) + Data([10]))
    }
}
