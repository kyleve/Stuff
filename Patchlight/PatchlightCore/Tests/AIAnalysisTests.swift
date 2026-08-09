import Foundation
import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct AIAnalysisTests {
    @Test func presetsKeepVersionedProviderModelAndBudgetMappings() throws {
        let fast = try AnalysisModelSelection(
            provider: .openAI,
            preset: .fast,
            advancedModelID: nil,
        )
        #expect(fast.modelID == "gpt-5.6-luna")
        #expect(fast.reasoningEffort == .low)
        #expect(fast.budget.diffBytes == 512 * 1024)
        #expect(fast.budget.extraContextBytes == 256 * 1024)
        #expect(fast.budget.maximumProviderCalls == 8)
        #expect(fast.budget.maximumTurns == 4)

        let openAIBalanced = try AnalysisModelSelection(
            provider: .openAI,
            preset: .balanced,
            advancedModelID: nil,
        )
        #expect(openAIBalanced.modelID == "gpt-5.6-terra")
        #expect(openAIBalanced.reasoningEffort == .medium)

        let balanced = try AnalysisModelSelection(
            provider: .anthropic,
            preset: .balanced,
            advancedModelID: nil,
        )
        #expect(balanced.modelID == "claude-sonnet-5")
        #expect(balanced.reasoningEffort == .medium)
        #expect(balanced.budget.diffBytes == 2 * 1024 * 1024)

        let deep = try AnalysisModelSelection(
            provider: .openAI,
            preset: .deep,
            advancedModelID: nil,
        )
        #expect(deep.modelID == "gpt-5.6-sol")
        #expect(deep.reasoningEffort == .high)
        #expect(deep.budget.diffBytes == 8 * 1024 * 1024)

        let anthropicFast = try AnalysisModelSelection(
            provider: .anthropic,
            preset: .fast,
            advancedModelID: nil,
        )
        #expect(anthropicFast.modelID == "claude-haiku-4-5-20251001")
        #expect(anthropicFast.reasoningEffort == .off)

        let anthropicDeep = try AnalysisModelSelection(
            provider: .anthropic,
            preset: .deep,
            advancedModelID: nil,
        )
        #expect(anthropicDeep.modelID == "claude-opus-5")
        #expect(anthropicDeep.reasoningEffort == .high)
        #expect(anthropicDeep.budget.extraContextBytes == 2 * 1024 * 1024)
        #expect(anthropicDeep.budget.maximumProviderCalls == 32)
        #expect(anthropicDeep.budget.maximumTurns == 8)
    }

    @Test func advancedPresetRequiresAndPreservesAnExplicitModelID() throws {
        #expect(throws: AIAnalysisError.invalidAdvancedModelID) {
            try AnalysisModelSelection(
                provider: .openAI,
                preset: .advanced,
                advancedModelID: "  ",
            )
        }
        let selection = try AnalysisModelSelection(
            provider: .anthropic,
            preset: .advanced,
            advancedModelID: " experimental-model-2026-08 ",
        )
        #expect(selection.modelID == "experimental-model-2026-08")
    }

    @Test func providerCredentialsAreIndependentAndIndividuallyRemovable() async throws {
        let store = InMemoryCredentialStore()
        let manager = ProviderCredentialManager(store: store)
        try await manager.set(ProviderAPIKey("openai-secret"), for: .openAI)
        try await manager.set(ProviderAPIKey("anthropic-secret"), for: .anthropic)

        #expect(try await manager.hasCredential(for: .openAI))
        #expect(try await manager.hasCredential(for: .anthropic))
        try await manager.remove(.openAI)
        #expect(try await !manager.hasCredential(for: .openAI))
        #expect(try await manager.hasCredential(for: .anthropic))
        #expect(try store.data(for: ProviderCredentialManager.credentialKey(
            for: .anthropic,
        )) == Data("anthropic-secret".utf8))
    }
}
