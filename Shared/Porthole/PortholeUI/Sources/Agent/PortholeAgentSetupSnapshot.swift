import Foundation
import PortholeAgent
import SwiftUI
import Synchronization

/// Uses the same journal and presentation path with in-memory protocol implementations.
struct PortholeAgentSetupSnapshot: View {
    private let result: Result<PortholeAgentPresentationModel, any Error>

    init(messages: [PortholeAgentMessage] = []) {
        result = Result {
            let store = try AgentPreviewTranscriptStore(data: JSONEncoder()
                .encode(PortholeAgentTranscript(
                    consentingProviders: [],
                    messages: messages,
                    operations: [],
                )))
            let journal = try PortholeAgentJournal(storage: store)
            return PortholeAgentPresentationModel(
                sessions: AgentPreviewSessionFactory(),
                credentials: AgentPreviewCredentialStore(),
                journal: journal,
                initialProvider: .openAI,
                initialModelID: "",
                instructions: "Inspect the selected app context.",
                reconcile: { _ in nil },
            )
        }
    }

    var body: some View {
        NavigationStack {
            switch result {
                case let .success(model): PortholeAgentView(model: model)
                case let .failure(error): Text("Preview failed: \(String(describing: error))")
            }
        }.portholeBroadwayRoot()
    }
}

private final class AgentPreviewTranscriptStore: PortholeAgentTranscriptStoring, Sendable {
    private let data: Mutex<Data?>
    init(data: Data?) {
        self.data = Mutex(data)
    }

    func load() throws -> Data? {
        data.withLock { $0 }
    }

    func save(_ data: Data) throws {
        self.data.withLock { $0 = data }
    }
}

private struct AgentPreviewSessionFactory: PortholeAgentSessionCreating {
    func create(configuration: PortholeAgentConfiguration) throws -> any PortholeAgentStreaming {
        throw PortholeAgentError.missingCredential(configuration.provider)
    }
}

private final class AgentPreviewCredentialStore: PortholeAgentCredentialEditing, Sendable {
    private let keys = Mutex<[PortholeAgentProvider: String]>([:])
    func store(apiKey: String, for provider: PortholeAgentProvider) throws {
        keys.withLock { $0[provider] = apiKey }
    }

    func remove(for provider: PortholeAgentProvider) throws {
        keys.withLock { $0[provider] = nil }
    }

    func apiKey(for provider: PortholeAgentProvider) throws -> String {
        guard let key = keys.withLock({ $0[provider] })
        else { throw PortholeAgentError.missingCredential(provider) }
        return key
    }
}
