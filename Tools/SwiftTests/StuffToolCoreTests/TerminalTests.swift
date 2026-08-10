import StuffToolCore
import Testing

struct TerminalTests {
    @Test func stringConvenienceWritesUTF8ToTheRequestedStream() async throws {
        let terminal = MemoryTerminal()

        try await terminal.write("hello ✓", to: .standardError)

        #expect(await terminal.standardOutput.isEmpty)
        #expect(await terminal.standardErrorText == "hello ✓")
    }
}
