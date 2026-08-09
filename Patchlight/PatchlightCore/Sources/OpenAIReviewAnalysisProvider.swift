import Foundation

/// Direct OpenAI Responses adapter. Turns are replayed locally and every
/// request sets `store: false`; no server-side conversation state is required.
public actor OpenAIReviewAnalysisProvider: ReviewAnalysisProvider {
    public nonisolated let provider = AIProvider.openAI
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
        precondition(selection.provider == .openAI)
        self.selection = selection
        self.credential = credential
        self.transport = transport
        self.tools = tools
        self.budget = budget
        modelID = selection.modelID
    }

    public func analyze(_ request: ReviewAnalysisRequest) async throws -> ReviewAnalysis {
        let start = Date()
        var input: [OpenAIInputItem] = [
            .message(role: "user", content: [.text(ProviderPrompt.review(request))]),
        ]
        var usage = AnalysisUsage.zero
        var localProviderCalls = 0

        while true {
            try Task.checkCancellation()
            try await budget.claimProviderCall()
            localProviderCalls += 1
            let response = try await send(OpenAIRequest(
                model: selection.modelID,
                store: false,
                instructions: ProviderPrompt.instructions,
                input: input,
                reasoning: OpenAIReasoning(effort: selection.reasoningEffort.rawValue),
                tools: ProviderAnalysisSchema.tools.map(OpenAITool.init),
                text: OpenAITextConfiguration(
                    format: OpenAITextFormat(
                        name: "patchlight_review_v1",
                        schema: ProviderAnalysisSchema.review,
                    ),
                ),
            ))
            usage = usage.adding(response.usageValue(providerCalls: 1))

            let calls = response.output.compactMap(\.functionCall)
            if !calls.isEmpty {
                try await budget.claimToolTurn()
                for call in calls {
                    guard let arguments = call.arguments.data(using: .utf8) else {
                        throw AIAnalysisError.invalidToolRequest
                    }
                    let decoded = try ProviderToolCallDecoder.call(
                        name: call.name,
                        arguments: arguments,
                    )
                    let output = try await tools.execute(decoded)
                    let outputData = try JSONEncoder.provider.encode(output)
                    guard let outputText = String(data: outputData, encoding: .utf8) else {
                        throw AIAnalysisError.invalidProviderResponse
                    }
                    input.append(.functionCall(
                        callID: call.callID,
                        name: call.name,
                        arguments: call.arguments,
                    ))
                    input.append(.functionOutput(callID: call.callID, output: outputText))
                }
                continue
            }

            guard let outputText = response.output.compactMap(\.outputText).last,
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
        var content: [OpenAIInputContent] = [.text(ProviderPrompt.image(request))]
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
        let response = try await send(OpenAIRequest(
            model: selection.modelID,
            store: false,
            instructions: ProviderPrompt.instructions,
            input: [.message(role: "user", content: content)],
            reasoning: OpenAIReasoning(effort: selection.reasoningEffort.rawValue),
            tools: [],
            text: OpenAITextConfiguration(
                format: OpenAITextFormat(
                    name: "patchlight_snapshot_v1",
                    schema: ProviderAnalysisSchema.image,
                ),
            ),
        ))
        guard let outputText = response.output.compactMap(\.outputText).last,
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

    private func send(_ value: OpenAIRequest) async throws -> OpenAIResponseWire {
        let body = try JSONEncoder.provider.encode(value)
        let response = try await transport.send(PatchlightHTTPRequest(
            method: .post,
            url: URL(string: "https://api.openai.com/v1/responses")!,
            headers: [
                "Authorization": "Bearer \(credential.value)",
                "Content-Type": "application/json",
            ],
            body: body,
        ))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw AIAnalysisError.providerFailure(
                statusCode: response.statusCode,
                message: OpenAIErrorWire.message(from: response.body),
            )
        }
        do {
            return try JSONDecoder().decode(OpenAIResponseWire.self, from: response.body)
        } catch {
            throw AIAnalysisError.invalidProviderResponse
        }
    }
}

private struct OpenAIRequest: Encodable {
    let model: String
    let store: Bool
    let instructions: String
    let input: [OpenAIInputItem]
    let reasoning: OpenAIReasoning
    let tools: [OpenAITool]
    let text: OpenAITextConfiguration
}

private struct OpenAIReasoning: Encodable {
    let effort: String
}

private struct OpenAITextConfiguration: Encodable {
    let format: OpenAITextFormat
}

private struct OpenAITextFormat: Encodable {
    let type = "json_schema"
    let name: String
    let strict = true
    let schema: JSONValue
}

private struct OpenAITool: Encodable {
    let type = "function"
    let name: String
    let description: String
    let parameters: JSONValue
    let strict = false

    init(_ definition: ProviderToolDefinition) {
        name = definition.name.rawValue
        description = definition.description
        parameters = definition.parameters
    }
}

private enum OpenAIInputItem: Encodable {
    case message(role: String, content: [OpenAIInputContent])
    case functionCall(callID: String, name: String, arguments: String)
    case functionOutput(callID: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
        case callID = "call_id"
        case name
        case arguments
        case output
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .message(role, content):
                try container.encode("message", forKey: .type)
                try container.encode(role, forKey: .role)
                try container.encode(content, forKey: .content)
            case let .functionCall(callID, name, arguments):
                try container.encode("function_call", forKey: .type)
                try container.encode(callID, forKey: .callID)
                try container.encode(name, forKey: .name)
                try container.encode(arguments, forKey: .arguments)
            case let .functionOutput(callID, output):
                try container.encode("function_call_output", forKey: .type)
                try container.encode(callID, forKey: .callID)
                try container.encode(output, forKey: .output)
        }
    }
}

private enum OpenAIInputContent: Encodable {
    case text(String)
    case image(Data)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case detail
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .text(text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case let .image(data):
                try container.encode("input_image", forKey: .type)
                try container.encode(
                    "data:image/png;base64,\(data.base64EncodedString())",
                    forKey: .imageURL,
                )
                try container.encode("high", forKey: .detail)
        }
    }
}

extension [OpenAIInputContent] {
    fileprivate var containsImage: Bool {
        contains {
            if case .image = $0 { true } else { false }
        }
    }
}

private struct OpenAIResponseWire: Decodable {
    let id: String
    let output: [OpenAIOutputItem]
    let usage: OpenAIUsageWire?

    func usageValue(providerCalls: Int) -> AnalysisUsage {
        AnalysisUsage(
            promptTokens: usage?.inputTokens,
            cachedPromptTokens: usage?.inputTokensDetails?.cachedTokens,
            outputTokens: usage?.outputTokens,
            reasoningTokens: usage?.outputTokensDetails?.reasoningTokens,
            providerCalls: providerCalls,
            toolCalls: 0,
            filesRetrieved: 0,
            bytesRetrieved: 0,
            durationMilliseconds: 0,
            requestID: id,
        )
    }
}

private struct OpenAIOutputItem: Decodable {
    let type: String
    let callID: String?
    let name: String?
    let arguments: String?
    let content: [OpenAIOutputContent]?

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case name
        case arguments
        case content
    }

    var functionCall: OpenAIFunctionCall? {
        guard type == "function_call", let callID, let name, let arguments else { return nil }
        return OpenAIFunctionCall(
            callID: callID,
            name: name,
            arguments: arguments,
        )
    }

    var outputText: String? {
        guard type == "message" else { return nil }
        return content?.first(where: { $0.type == "output_text" })?.text
    }
}

private struct OpenAIFunctionCall {
    let callID: String
    let name: String
    let arguments: String
}

private struct OpenAIOutputContent: Decodable {
    let type: String
    let text: String?
}

private struct OpenAIUsageWire: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let inputTokensDetails: OpenAIInputTokenDetails?
    let outputTokensDetails: OpenAIOutputTokenDetails?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokensDetails = "output_tokens_details"
    }
}

private struct OpenAIInputTokenDetails: Decodable {
    let cachedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

private struct OpenAIOutputTokenDetails: Decodable {
    let reasoningTokens: Int?

    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }
}

private struct OpenAIErrorWire: Decodable {
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
    fileprivate static var provider: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
