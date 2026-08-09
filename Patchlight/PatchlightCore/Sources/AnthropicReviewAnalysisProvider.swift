import Foundation

/// Direct Anthropic Messages adapter with locally replayed tool turns.
public actor AnthropicReviewAnalysisProvider: ReviewAnalysisProvider {
    public nonisolated let provider = AIProvider.anthropic
    public nonisolated let modelID: String

    private let selection: AnalysisModelSelection
    private let credential: ProviderAPIKey
    private let transport: any PatchlightHTTPTransport
    private let tools: AnalysisRepositoryTools
    private let budget: AnalysisRunBudgetController

    public init(
        selection: AnalysisModelSelection,
        credential: ProviderAPIKey,
        transport: any PatchlightHTTPTransport,
        tools: AnalysisRepositoryTools,
        budget: AnalysisRunBudgetController,
    ) {
        precondition(selection.provider == .anthropic)
        self.selection = selection
        self.credential = credential
        self.transport = transport
        self.tools = tools
        self.budget = budget
        modelID = selection.modelID
    }

    public func analyze(_ request: ReviewAnalysisRequest) async throws -> ReviewAnalysis {
        let start = Date()
        var messages = [AnthropicMessage(
            role: "user",
            content: [.text(ProviderPrompt.review(request))],
        )]
        var usage = AnalysisUsage.zero
        var localProviderCalls = 0

        while true {
            try Task.checkCancellation()
            try await budget.claimProviderCall()
            localProviderCalls += 1
            let response = try await send(AnthropicRequest(
                model: selection.modelID,
                maximumTokens: 8192,
                system: ProviderPrompt.instructions,
                messages: messages,
                tools: ProviderAnalysisSchema.tools.map(AnthropicTool.init),
                outputConfiguration: AnthropicOutputConfiguration(
                    effort: anthropicEffort,
                    format: AnthropicOutputFormat(schema: ProviderAnalysisSchema.review),
                ),
            ))
            usage = usage.adding(response.usageValue(providerCalls: 1))

            let calls = response.content.compactMap(\.toolUse)
            if !calls.isEmpty {
                try await budget.claimToolTurn()
                messages.append(AnthropicMessage(
                    role: "assistant",
                    content: response.content.compactMap(\.requestBlock),
                ))
                var results: [AnthropicRequestBlock] = []
                for call in calls {
                    let arguments = try JSONEncoder.anthropicProvider.encode(call.input)
                    let decoded = try ProviderToolCallDecoder.call(
                        name: call.name,
                        arguments: arguments,
                    )
                    let output = try await tools.execute(decoded)
                    let outputData = try JSONEncoder.anthropicProvider.encode(output)
                    guard let outputText = String(data: outputData, encoding: .utf8) else {
                        throw AIAnalysisError.invalidProviderResponse
                    }
                    results.append(.toolResult(toolUseID: call.id, content: outputText))
                }
                messages.append(AnthropicMessage(role: "user", content: results))
                continue
            }

            guard let outputText = response.content.compactMap(\.textValue).last,
                  let outputData = outputText.data(using: .utf8)
            else {
                throw AIAnalysisError.invalidProviderResponse
            }
            let validated = try ProviderOutputValidator.review(outputData, request: request)
            return ReviewAnalysis(
                hunks: validated.hunks,
                files: validated.files,
                summary: validated.summary,
                usage: AnalysisUsage(
                    promptTokens: usage.promptTokens,
                    cachedPromptTokens: usage.cachedPromptTokens,
                    outputTokens: usage.outputTokens,
                    reasoningTokens: usage.reasoningTokens,
                    providerCalls: localProviderCalls,
                    toolCalls: 0,
                    filesRetrieved: 0,
                    bytesRetrieved: 0,
                    durationMilliseconds: Int(Date().timeIntervalSince(start) * 1000),
                    requestID: response.id,
                ),
            )
        }
    }

    public func analyzeImages(
        _ request: SnapshotImageAnalysisRequest,
    ) async throws -> SnapshotImageAnalysis {
        let start = Date()
        var content: [AnthropicRequestBlock] = [.text(ProviderPrompt.image(request))]
        if let base = request.basePNGData {
            content.append(.text("The next image is the selected base snapshot."))
            content.append(.image(base))
        }
        if let head = request.headPNGData {
            content.append(.text("The next image is the selected head snapshot."))
            content.append(.image(head))
        }
        guard content.containsImage else { throw AIAnalysisError.invalidProviderResponse }

        try await budget.claimProviderCall()
        let response = try await send(AnthropicRequest(
            model: selection.modelID,
            maximumTokens: 8192,
            system: ProviderPrompt.instructions,
            messages: [AnthropicMessage(role: "user", content: content)],
            tools: [],
            outputConfiguration: AnthropicOutputConfiguration(
                effort: anthropicEffort,
                format: AnthropicOutputFormat(schema: ProviderAnalysisSchema.image),
            ),
        ))
        guard let outputText = response.content.compactMap(\.textValue).last,
              let outputData = outputText.data(using: .utf8)
        else {
            throw AIAnalysisError.invalidProviderResponse
        }
        let validated = try ProviderOutputValidator.image(outputData)
        let wireUsage = response.usageValue(providerCalls: 1)
        return SnapshotImageAnalysis(
            summary: validated.summary,
            findings: validated.findings,
            usage: AnalysisUsage(
                promptTokens: wireUsage.promptTokens,
                cachedPromptTokens: wireUsage.cachedPromptTokens,
                outputTokens: wireUsage.outputTokens,
                reasoningTokens: wireUsage.reasoningTokens,
                providerCalls: 1,
                toolCalls: 0,
                filesRetrieved: 0,
                bytesRetrieved: 0,
                durationMilliseconds: Int(Date().timeIntervalSince(start) * 1000),
                requestID: response.id,
            ),
        )
    }

    private var anthropicEffort: String? {
        switch selection.reasoningEffort {
            case .off: nil
            case .low: "low"
            case .medium: "medium"
            case .high: "high"
        }
    }

    private func send(_ value: AnthropicRequest) async throws -> AnthropicResponseWire {
        let body = try JSONEncoder.anthropicProvider.encode(value)
        let response = try await transport.send(PatchlightHTTPRequest(
            method: .post,
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "x-api-key": credential.value,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            ],
            body: body,
        ))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw AIAnalysisError.providerFailure(
                statusCode: response.statusCode,
                message: AnthropicErrorWire.message(from: response.body),
            )
        }
        do {
            return try JSONDecoder().decode(AnthropicResponseWire.self, from: response.body)
        } catch {
            throw AIAnalysisError.invalidProviderResponse
        }
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let maximumTokens: Int
    let system: String
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]
    let outputConfiguration: AnthropicOutputConfiguration

    enum CodingKeys: String, CodingKey {
        case model
        case maximumTokens = "max_tokens"
        case system
        case messages
        case tools
        case outputConfiguration = "output_config"
    }
}

private struct AnthropicOutputConfiguration: Encodable {
    let effort: String?
    let format: AnthropicOutputFormat
}

private struct AnthropicOutputFormat: Encodable {
    let type = "json_schema"
    let schema: JSONValue
}

private struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    init(_ definition: ProviderToolDefinition) {
        name = definition.name.rawValue
        description = definition.description
        inputSchema = definition.parameters
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicRequestBlock]
}

private enum AnthropicRequestBlock: Encodable {
    case text(String)
    case image(Data)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseID = "tool_use_id"
        case content
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .text(text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case let .image(data):
                try container.encode("image", forKey: .type)
                try container.encode(
                    AnthropicImageSource(data: data.base64EncodedString()),
                    forKey: .source,
                )
            case let .toolUse(id, name, input):
                try container.encode("tool_use", forKey: .type)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .name)
                try container.encode(input, forKey: .input)
            case let .toolResult(toolUseID, content):
                try container.encode("tool_result", forKey: .type)
                try container.encode(toolUseID, forKey: .toolUseID)
                try container.encode(content, forKey: .content)
        }
    }
}

extension [AnthropicRequestBlock] {
    fileprivate var containsImage: Bool {
        contains {
            if case .image = $0 { true } else { false }
        }
    }
}

private struct AnthropicImageSource: Encodable {
    let type = "base64"
    let mediaType = "image/png"
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct AnthropicResponseWire: Decodable {
    let id: String
    let content: [AnthropicResponseBlock]
    let usage: AnthropicUsageWire?

    func usageValue(providerCalls: Int) -> AnalysisUsage {
        AnalysisUsage(
            promptTokens: usage?.inputTokens,
            cachedPromptTokens: usage?.cacheReadInputTokens,
            outputTokens: usage?.outputTokens,
            reasoningTokens: nil,
            providerCalls: providerCalls,
            toolCalls: 0,
            filesRetrieved: 0,
            bytesRetrieved: 0,
            durationMilliseconds: 0,
            requestID: id,
        )
    }
}

private struct AnthropicResponseBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: JSONValue?

    var toolUse: AnthropicToolUse? {
        guard type == "tool_use", let id, let name, let input else { return nil }
        return AnthropicToolUse(id: id, name: name, input: input)
    }

    var textValue: String? {
        type == "text" ? text : nil
    }

    var requestBlock: AnthropicRequestBlock? {
        if let toolUse {
            return .toolUse(id: toolUse.id, name: toolUse.name, input: toolUse.input)
        }
        if let textValue { return .text(textValue) }
        return nil
    }
}

private struct AnthropicToolUse {
    let id: String
    let name: String
    let input: JSONValue
}

private struct AnthropicUsageWire: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

private struct AnthropicErrorWire: Decodable {
    struct Detail: Decodable {
        let message: String
    }

    let error: Detail

    static func message(from data: Data) -> String {
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            return String(value.error.message.prefix(1000))
        } catch {
            return "The response did not include a readable error."
        }
    }
}

extension JSONEncoder {
    fileprivate static var anthropicProvider: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
