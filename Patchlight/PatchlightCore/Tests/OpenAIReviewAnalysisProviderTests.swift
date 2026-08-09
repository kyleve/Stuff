import Foundation
import PatchlightCore
import Testing

struct OpenAIReviewAnalysisProviderTests {
    @Test func responsesToolLoopIsLocalStoredFalseAndValidated() async throws {
        let first = ProviderAnalysisTestSupport.response([
            "id": "resp-tool",
            "output": [[
                "type": "function_call",
                "call_id": "call-1",
                "name": "read_file",
                "arguments": "{\"revision\":\"head\",\"path\":\"Sources/App.swift\"}",
            ]],
            "usage": [
                "input_tokens": 100,
                "output_tokens": 20,
                "input_tokens_details": ["cached_tokens": 25],
                "output_tokens_details": ["reasoning_tokens": 7],
            ],
        ])
        let second = ProviderAnalysisTestSupport.response([
            "id": "resp-final",
            "output": [[
                "type": "message",
                "content": [[
                    "type": "output_text",
                    "text": ProviderAnalysisTestSupport.structuredReview(),
                ]],
            ]],
            "usage": ["input_tokens": 50, "output_tokens": 30],
        ])
        let transport = ScriptedHTTPTransport([.success(first), .success(second)])
        let budget = try ProviderAnalysisTestSupport.budget(provider: .openAI)
        let github = ProviderAnalysisTestSupport.github()
        let provider = try OpenAIReviewAnalysisProvider(
            selection: ProviderAnalysisTestSupport.selection(provider: .openAI),
            credential: ProviderAPIKey("openai-test-secret"),
            transport: transport,
            tools: ProviderAnalysisTestSupport.tools(github: github, budget: budget),
            budget: budget,
        )

        let analysis = try await provider.analyze(ProviderAnalysisTestSupport.request())

        #expect(analysis.hunks.map(\.assessment.hunkID.rawValue) == ["hunk-1"])
        #expect(analysis.hunks[0].findings.count == 1)
        #expect(analysis.hunks[0].findings[0].side == .head)
        #expect(analysis.usage.promptTokens == 150)
        #expect(analysis.usage.cachedPromptTokens == 25)
        #expect(analysis.usage.outputTokens == 50)
        #expect(analysis.usage.reasoningTokens == 7)
        #expect(analysis.usage.providerCalls == 2)
        #expect(analysis.usage.requestID == "resp-final")

        let requests = await transport.capturedRequests()
        #expect(requests.count == 2)
        #expect(requests
            .allSatisfy { $0.url.absoluteString == "https://api.openai.com/v1/responses" })
        #expect(requests.allSatisfy { $0.headers["Authorization"] == "Bearer openai-test-secret" })
        let firstBody = try jsonObject(requests[0])
        #expect(firstBody["store"] as? Bool == false)
        #expect(firstBody["model"] as? String == "gpt-5.6-terra")
        let secondBody = try jsonObject(requests[1])
        let input = try #require(secondBody["input"] as? [[String: Any]])
        #expect(input.contains { $0["type"] as? String == "function_call" })
        let toolOutput = try #require(input.first {
            $0["type"] as? String == "function_call_output"
        }?["output"] as? String)
        #expect(toolOutput.contains("let enabled = true"))
        let metrics = await budget.toolMetrics()
        #expect(metrics.toolCalls == 1)
        #expect(metrics.filesRetrieved == 1)
    }

    @Test func unknownHunkIDsFailClosedInsteadOfFilteringDeterministicWork() async throws {
        let response = ProviderAnalysisTestSupport.response([
            "id": "resp-invalid",
            "output": [[
                "type": "message",
                "content": [[
                    "type": "output_text",
                    "text": ProviderAnalysisTestSupport.structuredReview(hunkID: "invented"),
                ]],
            ]],
        ])
        let transport = ScriptedHTTPTransport([.success(response)])
        let budget = try ProviderAnalysisTestSupport.budget(provider: .openAI)
        let provider = try OpenAIReviewAnalysisProvider(
            selection: ProviderAnalysisTestSupport.selection(provider: .openAI),
            credential: ProviderAPIKey("secret"),
            transport: transport,
            tools: ProviderAnalysisTestSupport.tools(
                github: ProviderAnalysisTestSupport.github(),
                budget: budget,
            ),
            budget: budget,
        )

        await #expect(throws: AIAnalysisError.self) {
            try await provider.analyze(ProviderAnalysisTestSupport.request())
        }
    }

    @Test func imageAnalysisSendsOnlyTheExplicitlySelectedImages() async throws {
        let response = ProviderAnalysisTestSupport.response([
            "id": "resp-image",
            "output": [[
                "type": "message",
                "content": [[
                    "type": "output_text",
                    "text": "{\"summary\":\"One visual change.\",\"findings\":[{\"target\":\"head\",\"x\":0.1,\"y\":0.2,\"width\":0.3,\"height\":0.4,\"label\":\"Spacing\",\"explanation\":\"The inset changed.\",\"confidence\":0.9}]}",
                ]],
            ]],
            "usage": ["input_tokens": 12, "output_tokens": 8],
        ])
        let transport = ScriptedHTTPTransport([.success(response)])
        let budget = try ProviderAnalysisTestSupport.budget(provider: .openAI)
        let provider = try OpenAIReviewAnalysisProvider(
            selection: ProviderAnalysisTestSupport.selection(provider: .openAI),
            credential: ProviderAPIKey("secret"),
            transport: transport,
            tools: ProviderAnalysisTestSupport.tools(
                github: ProviderAnalysisTestSupport.github(),
                budget: budget,
            ),
            budget: budget,
        )

        let result = try await provider.analyzeImages(SnapshotImageAnalysisRequest(
            path: "Tests/Snapshots/Card.png",
            baseOID: PatchlightCoreTestSupport.objectID("c"),
            headOID: PatchlightCoreTestSupport.objectID("d"),
            basePNGData: Data([1, 2, 3]),
            headPNGData: Data([4, 5, 6]),
            metrics: nil,
        ))

        #expect(result.findings.count == 1)
        let request = try #require(await transport.capturedRequests().first)
        let body = try jsonObject(request)
        let input = try #require(body["input"] as? [[String: Any]])
        let message = try #require(input.first)
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.count(where: { $0["type"] as? String == "input_image" }) == 2)
        #expect((body["tools"] as? [Any])?.isEmpty == true)
    }

    private func jsonObject(_ request: PatchlightHTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any],
        )
    }
}
