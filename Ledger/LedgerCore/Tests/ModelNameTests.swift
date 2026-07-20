@_spi(Testing) import LedgerCore
import Testing

struct ModelNameTests {
    @Test func parsesClaudeWithHyphenatedVersionAndEffort() {
        let name = ModelName.parse("claude-opus-4-8-thinking-xhigh")
        #expect(name.displayName == "Claude Opus 4.8")
        #expect(name.badges == ["XHigh"])
    }

    @Test func keepsDottedVersionsAndMapsEffort() {
        let name = ModelName.parse("composer-2.5-fast")
        #expect(name.displayName == "Composer 2.5")
        #expect(name.badges == ["Fast"])
    }

    @Test func dropsThinkingFromTheName() {
        let name = ModelName.parse("claude-fable-5-thinking-high")
        #expect(name.displayName == "Claude Fable 5")
        #expect(name.badges == ["High"])
    }

    @Test func handlesEffortBeforeThinking() {
        let name = ModelName.parse("claude-4.6-sonnet-high-thinking")
        #expect(name.displayName == "Claude 4.6 Sonnet")
        #expect(name.badges == ["High"])
    }

    @Test func mapsUnderscoreIdentifiers() {
        let name = ModelName.parse("github_bugbot")
        #expect(name.displayName == "GitHub Bugbot")
        #expect(name.badges.isEmpty)
    }

    @Test func extractsNonMaxModeBeforeEffort() {
        let name = ModelName.parse("non-max-claude-opus-4-8-thinking-xhigh")
        #expect(name.displayName == "Claude Opus 4.8")
        #expect(name.badges == ["Non-max", "XHigh"])
    }

    @Test func dropsHostingPrefix() {
        let name = ModelName.parse("cursor-grok-4.5-high")
        #expect(name.displayName == "Grok 4.5")
        #expect(name.badges == ["High"])
    }

    @Test func keepsFamilyWordsLikeSol() {
        let name = ModelName.parse("gpt-5.6-sol-high")
        #expect(name.displayName == "GPT 5.6 Sol")
        #expect(name.badges == ["High"])
    }

    @Test func titleCasesUnknownModels() {
        let name = ModelName.parse("mistral-large-2")
        #expect(name.displayName == "Mistral Large 2")
        #expect(name.badges.isEmpty)
    }

    @Test func emptyFallsBackToRaw() {
        #expect(ModelName.parse("").displayName == "")
        #expect(ModelName.parse("   ").displayName == "   ")
    }
}
