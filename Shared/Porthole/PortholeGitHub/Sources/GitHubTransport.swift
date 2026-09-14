import Foundation

/// A transport response that never exposes an authenticated request in an error.
public struct GitHubHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol GitHubHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse
}

public struct GitHubURLSessionTransport: GitHubHTTPTransport {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        let (body, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key).lowercased()] = String(describing: field.value)
        }
        return GitHubHTTPResponse(statusCode: response.statusCode, headers: headers, body: body)
    }
}

public enum GitHubError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidIdentifier
    case invalidPath
    case unauthenticated
    case credentialExpired
    case requestFailed(statusCode: Int)
    case busy
    case authorizationExpired
    case authorizationDenied
    case authorizationFailed(code: String)
    case noAuthorization
    case incompleteRepositoryTree
    case unsupportedFile
    case fileTooLarge
    case missingBaseFile
    case emptyPatch
    case personalEvidenceApprovalRequired
    case branchConflict
    case accountChanged
    case pullRequestConflict
    case publicationReconciliationRequired
    case publicationUncertain(GitHubPublicationStep)
}

extension GitHubError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .invalidResponse: "GitHub returned an invalid response."
            case .invalidIdentifier: "The repository identifier is invalid."
            case .invalidPath: "The repository path is invalid."
            case .unauthenticated: "Sign in to GitHub to continue."
            case .credentialExpired: "Your GitHub sign-in expired. Sign in again."
            case let .requestFailed(statusCode): "GitHub returned HTTP \(statusCode)."
            case .busy: "A GitHub operation is already in progress."
            case .authorizationExpired: "The sign-in code expired. Request a new code."
            case .authorizationDenied: "GitHub sign-in was declined."
            case let .authorizationFailed(code): "GitHub sign-in failed: \(code)."
            case .noAuthorization: "Request a GitHub sign-in code first."
            case .incompleteRepositoryTree: "GitHub returned an incomplete repository tree."
            case .unsupportedFile: "This file cannot be edited as UTF-8 text."
            case .fileTooLarge: "This file exceeds the workspace size limit."
            case .missingBaseFile: "The file is absent from the repository base."
            case .emptyPatch: "The patch has no changes."
            case .personalEvidenceApprovalRequired: "Approve personal diagnostic evidence for this exact proposal on the phone before publication."
            case .branchConflict: "The publication branch contains a different commit."
            case .accountChanged: "The GitHub account changed. Sign in with the proposal’s original account and retry it."
            case .pullRequestConflict: "The publication branch belongs to a different pull request."
            case .publicationReconciliationRequired: "Retry the saved proposal to confirm its GitHub publication before changing this workspace."
            case let .publicationUncertain(step): "GitHub may have completed \(step.rawValue). Retry this proposal to reconcile its state."
        }
    }
}
