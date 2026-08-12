import Foundation
@_spi(Testing) import StuffToolCore
import Testing

struct TerminalTests {
    @Test func stringConvenienceWritesUTF8ToTheRequestedStream() async throws {
        let terminal = MemoryTerminal()

        try await terminal.write("hello ✓", to: .standardError)

        #expect(await terminal.standardOutput.isEmpty)
        #expect(await terminal.standardErrorText == "hello ✓")
    }

    @Test func standardErrorOnlyTerminalSuppressesMachineReadableOutput() async throws {
        let base = MemoryTerminal()
        let terminal = StandardErrorOnlyTerminal(base: base)

        try await terminal.write("UDID\n", to: .standardOutput)
        try await terminal.write("booting\n", to: .standardError)

        #expect(await base.standardOutputText.isEmpty)
        #expect(await base.standardErrorText == "booting\n")
        #expect(await terminal.isInputInteractive() == false)
        #expect(try await terminal.readLine(prompt: "continue") == nil)
    }

    @Test func standardTerminalWritesPromptsToStandardError() async throws {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let terminal = StandardTerminal(
            standardOutput: standardOutput.fileHandleForWriting,
            standardError: standardError.fileHandleForWriting,
            lineReader: { "yes" },
        )

        let response = try await terminal.readLine(prompt: "Continue? ")
        try standardOutput.fileHandleForWriting.close()
        try standardError.fileHandleForWriting.close()

        #expect(response == "yes")
        #expect(standardOutput.fileHandleForReading.readDataToEndOfFile().isEmpty)
        #expect(String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self,
        ) == "Continue? ")
    }
}
