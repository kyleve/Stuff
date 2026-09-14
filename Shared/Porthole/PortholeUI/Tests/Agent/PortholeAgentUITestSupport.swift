import Foundation
@testable import PortholeAgent
import Synchronization

final class AgentUITestStorage: PortholeAgentTranscriptStoring, Sendable {
    private let data = Mutex<Data?>(nil)
    func load() throws -> Data? {
        data.withLock { $0 }
    }

    func save(_ data: Data) throws {
        self.data.withLock { $0 = data }
    }
}

final class AgentUITestCredentials: PortholeAgentCredentialEditing, Sendable {
    private let values = Mutex<[PortholeAgentProvider: String]>([:])
    func store(apiKey: String, for provider: PortholeAgentProvider) throws {
        values.withLock { $0[provider] = apiKey }
    }

    func remove(for provider: PortholeAgentProvider) throws {
        _ = values.withLock { $0.removeValue(forKey: provider) }
    }

    func apiKey(for provider: PortholeAgentProvider) throws -> String {
        guard let key = values.withLock({ $0[provider] })
        else { throw PortholeAgentError.missingCredential(provider) }
        return key
    }
}

final class AgentUITestSession: PortholeAgentStreaming, Sendable {
    private let journal: PortholeAgentJournal
    private let suspend: Bool
    private let task = Mutex<Task<Void, Never>?>(nil)
    let started = AsyncStream.makeStream(of: Bool.self)

    init(journal: PortholeAgentJournal, suspend: Bool) {
        self.journal = journal
        self.suspend = suspend
    }

    func stream(messages: [PortholeAgentMessage])
        -> AsyncThrowingStream<PortholeAgentEvent, any Error>
    {
        AsyncThrowingStream { continuation in
            task.withLock { task in
                task = Task { [self] in
                    do {
                        try await journal.prepare(messages: messages)
                        started.continuation.yield(true)
                        if suspend { try await Task.sleep(for: .seconds(3600)) }
                        let message = PortholeAgentMessage.assistant(
                            text: "A recorded diagnostic.",
                            toolCalls: [],
                        )
                        try await journal.append(messages: [message])
                        continuation.yield(.text("A recorded diagnostic."))
                        continuation.yield(.message(message))
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { [self] _ in cancel() }
        }
    }

    func cancel() {
        task.withLock { $0 }?.cancel()
    }
}

final class AgentUITestFactory: PortholeAgentSessionCreating, Sendable {
    private let session: AgentUITestSession
    private let values = Mutex<[PortholeAgentConfiguration]>([])
    var configurations: [PortholeAgentConfiguration] {
        values.withLock { $0 }
    }

    init(session: AgentUITestSession) {
        self.session = session
    }

    func create(configuration: PortholeAgentConfiguration) throws -> any PortholeAgentStreaming {
        values.withLock { $0.append(configuration) }
        return session
    }
}
