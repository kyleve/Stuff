import Foundation

/// An unreadable or conflicting correction history must never resurrect excluded GPS presence.
public enum SampleAttributionPersistenceError: Error, Sendable, Equatable {
    case incompleteHistory
    case conflictingRevision(id: UUID)
}
