import Foundation

/// The GitHub user ID that owns an account-scoped Patchlight world.
public struct PatchlightAccountID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        precondition(rawValue > 0, "A GitHub account ID must be positive")
        self.rawValue = rawValue
    }
}

/// A GitHub App installation visible to the signed-in user.
public struct GitHubInstallationID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        precondition(rawValue > 0, "A GitHub installation ID must be positive")
        self.rawValue = rawValue
    }
}

/// A GitHub repository identity that remains stable across display-name reuse.
public struct RepositoryID: Hashable, Codable, Sendable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        precondition(rawValue > 0, "A repository ID must be positive")
        self.rawValue = rawValue
    }
}

/// The rename-sensitive coordinates used only when constructing GitHub routes.
public struct RepositoryCoordinates: Hashable, Codable, Sendable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        precondition(!owner.isEmpty, "A repository owner must not be empty")
        precondition(!name.isEmpty, "A repository name must not be empty")
        self.owner = owner
        self.name = name
    }

    public var displayName: String {
        "\(owner)/\(name)"
    }
}

/// A pull request's repository-scoped number.
public struct PullRequestID: Hashable, Codable, Sendable {
    public let repository: RepositoryID
    public let number: Int

    public init(repository: RepositoryID, number: Int) {
        precondition(number > 0, "A pull request number must be positive")
        self.repository = repository
        self.number = number
    }

    public var storageKey: String {
        "\(repository.rawValue):\(number)"
    }
}

/// An exact Git object identity, kept typed until an HTTP or persistence boundary.
public struct GitObjectID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A Git object ID must not be empty")
        self.rawValue = rawValue
    }

    /// Validates an object ID received from an untrusted wire response.
    public init(validating wireValue: String) throws {
        guard [40, 64].contains(wireValue.count),
              wireValue.allSatisfy(\.isHexDigit)
        else {
            throw GitObjectIDError.invalidWireValue
        }
        rawValue = wireValue.lowercased()
    }
}

public enum GitObjectIDError: LocalizedError, Equatable, Sendable {
    case invalidWireValue

    public var errorDescription: String? {
        "GitHub returned an invalid Git object ID."
    }
}
