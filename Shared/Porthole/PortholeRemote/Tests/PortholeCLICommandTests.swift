import PortholeRemote
import Testing

struct PortholeCLICommandTests {
    @Test func validatesArityAndKeepsCredentialsOutOfArguments() throws {
        #expect(try PortholeCLICommand.parse([]) == .help)
        #expect(try PortholeCLICommand.parse(["pair"]) == .pair)
        #expect(throws: PortholeRemoteError.invalidMessage) { try PortholeCLICommand.parse([
            "pair",
            "secret",
        ]) }
        #expect(throws: PortholeRemoteError.invalidMessage) { try PortholeCLICommand.parse([
            "approve",
            "operation",
        ]) }
        #expect(throws: PortholeRemoteError.invalidMessage) { try PortholeCLICommand.parse([
            "invoke",
            "app",
        ]) }
        #expect(try PortholeCLICommand.parse(["invoke", "Where", "call.json"]) == .invoke(
            server: "Where",
            invocationFile: "call.json",
        ))
        #expect(try PortholeCLICommand.parse(["mcp", "Where"]) == .mcp(server: "Where"))
    }
}
