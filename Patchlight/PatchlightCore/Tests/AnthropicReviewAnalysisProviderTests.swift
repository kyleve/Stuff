import Foundation
import PatchlightCore
import Testing

struct AnthropicReviewAnalysisProviderTests {
    @Test func messagesToolLoopReplaysLocallyAndUsesStructuredOutput() async throws {
        let first = ProviderAnalysisTestSupport.response([
            "id": "msg-tool",
            "content": [[
                "type": "tool_use",
                "id": "tool-1",
                "name": "search_paths",
                "input": ["revision": "head", "query": "App", "limit": 10],
            ]],
            "usage": [
                "input_tokens": 80,
                "output_tokens": 15,
                "cache_read_input_tokens": 10,
            ],
        ])
        let second = ProviderAnalysisTestSupport.response([
            "id": "msg-final",
            "content": [[
                "type": "text",
                "text": ProviderAnalysisTestSupport.structuredReview(),
            ]],
            "usage": ["input_tokens": 40, "output_tokens": 25],
        ])
        let transport = ScriptedHTTPTransport([.success(first), .success(second)])
        let budget = try ProviderAnalysisTestSupport.budget(provider: .anthropic)
        let provider = try AnthropicReviewAnalysisProvider(
            selection: ProviderAnalysisTestSupport.selection(provider: .anthropic),
            credential: ProviderAPIKey("anthropic-test-secret"),
            transport: transport,
            tools: ProviderAnalysisTestSupport.tools(
                github: ProviderAnalysisTestSupport.github(),
                budget: budget,
            ),
            budget: budget,
        )

        let analysis = try await provider.analyze(ProviderAnalysisTestSupport.request())

        #expect(analysis.hunks.map(\.assessment.hunkID.rawValue) == ["hunk-1"])
        #expect(analysis.usage.promptTokens == 120)
        #expect(analysis.usage.cachedPromptTokens == 10)
        #expect(analysis.usage.outputTokens == 40)
        #expect(analysis.usage.providerCalls == 2)
        #expect(analysis.usage.requestID == "msg-final")

        let requests = await transport.capturedRequests()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.url.absoluteString == "https://api.anthropic.com/v1/messages"
        })
        #expect(requests.allSatisfy { $0.headers["x-api-key"] == "anthropic-test-secret" })
        let firstBody = try jsonObject(requests[0])
        #expect(firstBody["model"] as? String == "claude-sonnet-5")
        let outputConfiguration = try #require(firstBody["output_config"] as? [String: Any])
        #expect(outputConfiguration["effort"] as? String == "medium")
        let secondBody = try jsonObject(requests[1])
        let messages = try #require(secondBody["messages"] as? [[String: Any]])
        let userToolResults = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(userToolResults.contains { $0["type"] as? String == "tool_result" })
        #expect(userToolResults.description.contains("Sources/App.swift"))
        let metrics = await budget.toolMetrics()
        #expect(metrics.toolCalls == 1)
        #expect(metrics.filesRetrieved == 0)
    }

    @Test func imageAnalysisUsesSeparateSelectedImageContent() async throws {
        let response = ProviderAnalysisTestSupport.response([
            "id": "msg-image",
            "content": [[
                "type": "text",
                "text": "{\"summary\":\"Expected visual update.\",\"findings\":[]}",
            ]],
            "usage": ["input_tokens": 10, "output_tokens": 5],
        ])
        let transport = ScriptedHTTPTransport([.success(response)])
        let budget = try ProviderAnalysisTestSupport.budget(provider: .anthropic)
        let provider = try AnthropicReviewAnalysisProvider(
            selection: ProviderAnalysisTestSupport.selection(provider: .anthropic),
            credential: ProviderAPIKey("secret"),
            transport: transport,
            tools: ProviderAnalysisTestSupport.tools(
                github: ProviderAnalysisTestSupport.github(),
                budget: budget,
            ),
            budget: budget,
        )

        let analysis = try await provider.analyzeImages(SnapshotImageAnalysisRequest(
            path: "Tests/Snapshots/Card.png",
            baseOID: nil,
            headOID: PatchlightCoreTestSupport.objectID("d"),
            basePNGData: nil,
            headPNGData: Data([4, 5, 6]),
            metrics: nil,
        ))

        #expect(analysis.summary == "Expected visual update.")
        let request = try #require(await transport.capturedRequests().first)
        let body = try jsonObject(request)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.count(where: { $0["type"] as? String == "image" }) == 1)
        #expect((body["tools"] as? [Any])?.isEmpty == true)
    }

    private func jsonObject(_ request: PatchlightHTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any],
        )
    }
}
