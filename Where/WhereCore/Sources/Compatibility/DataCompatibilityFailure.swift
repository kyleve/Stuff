import Foundation

/// Retains the original verification error through observable state and blocked store/intent APIs.
/// Equality identifies the same failure occurrence, so copying state preserves its identity and a
/// new failed verification remains observable even if its display message is unchanged.
public final class DataCompatibilityFailure: Error, Sendable, Equatable {
    public let error: any Error

    public init(_ error: any Error) {
        self.error = error
    }

    public static func == (lhs: DataCompatibilityFailure, rhs: DataCompatibilityFailure) -> Bool {
        lhs === rhs
    }

    /// A successful upgrade command must be followed by the expected local requirement.
    struct UnchangedRequirement: LocalizedError {
        let expected: DataCompatibilityVersion
        let observed: DataCompatibilityVersion
        var errorDescription: String? {
            "The shared version did not advance."
        }
    }
}
