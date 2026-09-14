import Foundation

public protocol PortholeAgentStreaming: Sendable {
    func stream(messages: [PortholeAgentMessage])
        -> AsyncThrowingStream<PortholeAgentEvent, any Error>
    func cancel()
}

public protocol PortholeAgentSessionCreating: Sendable {
    func create(configuration: PortholeAgentConfiguration) throws -> any PortholeAgentStreaming
}

/// Holds the shared native boundaries while each request selects its provider and model.
public struct PortholeAgentFactory: PortholeAgentSessionCreating, Sendable {
    private let credentials: any PortholeAgentCredentialStore
    private let tools: [PortholeAgentTool]
    private let journal: PortholeAgentJournal
    private let redaction: PortholeAgentRedaction
    private let executor: PortholeAgentSession.Executor

    public init(
        credentials: any PortholeAgentCredentialStore,
        tools: [PortholeAgentTool],
        journal: PortholeAgentJournal,
        redaction: PortholeAgentRedaction,
        executor: @escaping PortholeAgentSession.Executor,
    ) {
        self.credentials = credentials
        self.tools = tools
        self.journal = journal
        self.redaction = redaction
        self.executor = executor
    }

    public func create(configuration: PortholeAgentConfiguration) throws
        -> any PortholeAgentStreaming
    {
        var activeRedaction = redaction
        for provider in PortholeAgentProvider.allCases {
            do {
                activeRedaction = try activeRedaction
                    .including(secret: credentials.apiKey(for: provider))
            } catch PortholeAgentError.missingCredential { continue }
        }
        return try PortholeAgentSession(
            configuration: configuration,
            credentials: credentials,
            tools: tools,
            journal: journal,
            redaction: activeRedaction,
            executor: executor,
        )
    }
}
