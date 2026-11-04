/// Supported shared contracts and the version used when activating new behavior.
/// Minor and patch differences identify resolver policy, not access eligibility.
public struct DataCompatibilityPolicy: Hashable, Sendable {
    public let current: DataSemanticsVersion
    public let supportedMajors: Set<UInt>

    public init(current: DataSemanticsVersion, supportedMajors: Set<UInt>) {
        precondition(supportedMajors.contains(current.major))
        self.current = current
        self.supportedMajors = supportedMajors
    }

    /// Foundation builds understand the existing contract and version envelopes. Activation of
    /// the new recording contract belongs to the completed stack's deployment configuration.
    public static let foundation = Self(
        current: .init(major: 0, minor: 1, patch: 0),
        supportedMajors: [0],
    )

    public func validate(requiredMajor: UInt) throws {
        guard supportedMajors.contains(requiredMajor) else {
            throw DataCompatibilityError.updateRequired(requiredMajor: requiredMajor)
        }
    }

    public func decode<T>(
        authoredWith version: DataSemanticsVersion,
        _ payload: () throws -> T,
    ) throws -> T {
        try validate(requiredMajor: version.major)
        return try payload()
    }
}

public enum DataCompatibilityError: Error, Equatable {
    case updateRequired(requiredMajor: UInt)
    case verificationRequired
    case accountChanged
    case incompleteRecord
    case conflictingRecord
    case unsupportedStore
    case concurrentChange
    case upgradeRequiresConfirmation
    case activationNotReady
}

/// Marks a failure at admission without discarding the original decoding or I/O error.
struct DataCompatibilityAdmissionError: Error {
    let underlyingError: any Error
}
