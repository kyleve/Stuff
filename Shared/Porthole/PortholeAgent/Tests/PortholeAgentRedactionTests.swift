@testable import PortholeAgent
import PortholeCore
import Testing

struct PortholeAgentRedactionTests {
    @Test func removesNestedCredentialsAndKnownSecrets() {
        let redaction = PortholeAgentRedaction(secrets: ["known-secret"])
        #expect(redaction.value(.object([
            "api_key": .string("unknown-secret"),
            "evidence": .array([.string("prefix known-secret suffix")]),
        ])) == .object([
            "api_key": .string("[REDACTED]"),
            "evidence": .array([.string("prefix [REDACTED] suffix")]),
        ]))
    }

    @Test func waitsForSecretBoundariesAcrossChunks() {
        let redaction = PortholeAgentRedaction(secrets: ["abcdef"])
        var buffer = "prefix abc"
        var output = redaction.consume(&buffer, flush: false)
        buffer += "def suffix"
        output += redaction.consume(&buffer, flush: false)
        output += redaction.consume(&buffer, flush: true)
        #expect(output == "prefix [REDACTED] suffix")
    }
}
