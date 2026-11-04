import Foundation

/// The shared-data contract and exact automatic assessment policy, independent of app releases.
public struct DataSemanticsVersion: Hashable, Sendable, Comparable {
    public let major: UInt
    public let minor: UInt
    public let patch: UInt

    public init(major: UInt, minor: UInt, patch: UInt) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
