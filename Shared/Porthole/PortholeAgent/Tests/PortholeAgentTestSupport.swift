import AI
import Foundation
@_spi(Testing) @testable import PortholeAgent
import PortholeCore
import Synchronization
import Testing

final class AgentTestWorkspace: Sendable {
    let directory: URL
    var journalURL: URL {
        directory.appendingPathComponent("transcript.json")
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record(error) }
    }
}

final class ScriptedAgentModel: LanguageModel, Sendable {
    private struct State {
        var steps: [[StreamPart]]
        var requests: [LanguageModelRequest] = []
    }

    let provider = "test"
    let modelID = "test-model"
    private let state: Mutex<State>

    init(steps: [[StreamPart]]) {
        state = Mutex(State(steps: steps))
    }

    var requests: [LanguageModelRequest] {
        state.withLock { $0.requests }
    }

    func stream(_ request: LanguageModelRequest) async throws
        -> AsyncThrowingStream<StreamPart, any Error>
    {
        let parts = try state.withLock { state in
            state.requests.append(request)
            guard !state.steps.isEmpty else { throw PortholeAgentError.incompleteResponse }
            return state.steps.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

func agentTestConfiguration(provider: PortholeAgentProvider = .openAI)
    -> PortholeAgentConfiguration
{
    PortholeAgentConfiguration(
        provider: provider,
        modelID: "test-model",
        instructions: "Diagnose.",
        maxSteps: 4,
        maxOutputTokens: 100,
        duration: .seconds(10),
    )
}

func agentTestTool() -> PortholeAgentTool {
    PortholeAgentTool(
        toolID: .init(rawValue: "inspect"),
        description: "Inspect the app",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
    )
}
