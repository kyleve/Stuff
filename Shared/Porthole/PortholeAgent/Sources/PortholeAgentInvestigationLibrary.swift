import Foundation
import Synchronization

public struct PortholeAgentInvestigation: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let origin: PortholeAgentOrigin
}

/// Separate files keep late completions attached to their original investigation.
public final class PortholeAgentInvestigationLibrary: Sendable {
    private struct Index: Codable {
        let formatVersion: Int
        var selected: UUID?
        var investigations: [PortholeAgentInvestigation]
    }

    private struct State {
        var index: Index
        var journals: [UUID: PortholeAgentJournal] = [:]
    }

    public let anchorURL: URL
    private let directory: URL
    private let indexStore: PortholeAgentFileTranscriptStore
    private let state: Mutex<State>

    public init(anchorURL: URL) throws {
        self.anchorURL = anchorURL
        directory = anchorURL.deletingPathExtension().appendingPathExtension("investigations")
        indexStore = PortholeAgentFileTranscriptStore(url: directory
            .appendingPathComponent("selection.json"))
        let index: Index
        if let data = try indexStore.load() {
            index = try JSONDecoder().decode(Index.self, from: data)
            guard index.formatVersion == 1
            else { throw PortholeAgentError.unsupportedJournalVersion(index.formatVersion) }
            guard Set(index.investigations.map(\.id)).count == index.investigations.count
            else { throw PortholeAgentError.operationMismatch }
        } else {
            index = Index(formatVersion: 1, selected: nil, investigations: [])
        }
        state = Mutex(State(index: index))
    }

    public func investigations() -> [PortholeAgentInvestigation] {
        state.withLock { $0.index.investigations.sorted { $0.createdAt > $1.createdAt } }
    }

    public func selectedOrCreate(origin: PortholeAgentOrigin) throws -> PortholeAgentInvestigation {
        try state.withLock { state in
            if let selected = state.index.selected {
                guard let result = state.index.investigations.first(where: { $0.id == selected })
                else { throw PortholeAgentError.operationMismatch }
                return result
            }
            return try create(origin: origin, state: &state)
        }
    }

    public func create(origin: PortholeAgentOrigin) throws -> PortholeAgentInvestigation {
        try state.withLock { state in try create(origin: origin, state: &state) }
    }

    private func create(
        origin: PortholeAgentOrigin,
        state: inout State,
    ) throws -> PortholeAgentInvestigation {
        let investigation = PortholeAgentInvestigation(
            id: UUID(),
            title: origin.title,
            createdAt: Date(),
            origin: origin,
        )
        let store = transcriptStore(for: investigation.id)
        let document = PortholeAgentTranscript(
            consentingProviders: [],
            messages: [],
            operations: [],
            originalOrigin: origin,
        )
        try store.save(JSONEncoder().encode(document))
        var index = state.index
        index.investigations.append(investigation)
        index.selected = investigation.id
        try indexStore.save(JSONEncoder().encode(index))
        state.index = index
        return investigation
    }

    public func select(investigationID: UUID) throws {
        try state.withLock { state in
            guard state.index.investigations.contains(where: { $0.id == investigationID })
            else { throw PortholeAgentError.operationMismatch }
            var index = state.index
            index.selected = investigationID
            try indexStore.save(JSONEncoder().encode(index))
            state.index = index
        }
    }

    public func journal(for investigation: PortholeAgentInvestigation) throws
        -> PortholeAgentJournal
    {
        try state.withLock { state in
            guard state.index.investigations.contains(investigation)
            else { throw PortholeAgentError.operationMismatch }
            if let journal = state.journals[investigation.id] { return journal }
            let journal = try PortholeAgentJournal(
                storage: transcriptStore(for: investigation.id),
                originalOrigin: investigation.origin,
            )
            guard journal.originalOrigin == investigation.origin
            else { throw PortholeAgentError.operationMismatch }
            state.journals[investigation.id] = journal
            return journal
        }
    }

    private func transcriptStore(for investigationID: UUID) -> PortholeAgentFileTranscriptStore {
        PortholeAgentFileTranscriptStore(url: directory
            .appendingPathComponent(investigationID.uuidString).appendingPathExtension("json"))
    }
}
