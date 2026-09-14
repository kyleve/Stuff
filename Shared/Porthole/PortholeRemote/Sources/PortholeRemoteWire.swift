import Foundation
import PortholeCore

public enum PortholeRemoteError: Error, Sendable, Equatable, LocalizedError {
    case disabled
    case invalidMessage
    case frameTooLarge
    case disconnected
    case connectionBusy
    case timedOut
    case untrustedPeer
    case enrollmentExpired
    case invalidEnrollment
    case keychain(Int32)
    case invalidIdentity
    case remoteFailure(String)

    public var errorDescription: String? {
        switch self {
            case .disabled: "Remote access is disabled."
            case .invalidMessage: "The request is invalid. Check its command, schema, and required fields."
            case .frameTooLarge: "The request or response exceeds the remote message limit. Use a smaller page."
            case .disconnected: "The connection ended. An operation may already have completed."
            case .connectionBusy: "Another request is using this connection. Wait for it to finish."
            case .timedOut: "The connection timed out. An operation may already have completed."
            case .untrustedPeer: "This peer is not enrolled or its certificate has changed."
            case .enrollmentExpired: "The invitation expired or was already used. Create a new invitation on the device."
            case .invalidEnrollment: "The invitation or enrollment request is invalid."
            case let .keychain(status): "Keychain access failed (\(status))."
            case .invalidIdentity: "The TLS identity is invalid or expired."
            case let .remoteFailure(message): message
        }
    }
}

public struct PortholeRemoteApplication: Sendable, Equatable, Codable {
    public let applicationID: UUID
    public let name: String
    public let scopes: [PortholeScopeToken]

    public init(applicationID: UUID, name: String, scopes: [PortholeScopeToken]) {
        self.applicationID = applicationID
        self.name = name
        self.scopes = scopes
    }
}

public struct PortholeCapabilityPage: Sendable, Codable {
    public let offset: Int
    public let total: Int
    public let items: [PortholeCapability]

    public init(offset: Int, total: Int, items: [PortholeCapability]) {
        self.offset = offset
        self.total = total
        self.items = items
    }
}

/// Versioned operations deliberately omit an approval method. Only the application UI can approve.
public struct PortholeRemoteRequest: Sendable, Codable {
    public enum Operation: Sendable, Codable {
        case application
        case capabilities(scope: PortholeScopeToken, offset: Int, limit: Int)
        case invoke(PortholeInvocation)
    }

    public let version: Int
    public let requestID: UUID
    public let operation: Operation

    public init(requestID: UUID, operation: Operation) {
        version = 1
        self.requestID = requestID
        self.operation = operation
    }
}

public struct PortholeRemoteResponse: Sendable, Codable {
    public enum Result: Sendable, Codable {
        case application(PortholeRemoteApplication)
        case capabilities(PortholeCapabilityPage)
        case value(PortholeValue)
        case approvalRequired(PortholeActionProposal)
        case failure(code: String, message: String)
    }

    public let version: Int
    public let requestID: UUID
    public let result: Result

    public init(requestID: UUID, result: Result) {
        version = 1
        self.requestID = requestID
        self.result = result
    }
}

/// Four-byte network-order lengths bound allocations before a JSON decoder sees network input.
enum PortholeRemoteFraming {
    static let maximumBytes = 4 * 1024 * 1024

    static func frame(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw PortholeRemoteError.invalidMessage }
        guard data.count <= maximumBytes else { throw PortholeRemoteError.frameTooLarge }
        let size = UInt32(data.count)
        return Data([
            UInt8((size >> 24) & 255),
            UInt8((size >> 16) & 255),
            UInt8((size >> 8) & 255),
            UInt8(size & 255),
        ]) + data
    }

    static func size(_ header: Data) throws -> Int {
        guard header.count == 4 else { throw PortholeRemoteError.invalidMessage }
        let value = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard value > 0, value <= maximumBytes else { throw PortholeRemoteError.frameTooLarge }
        return Int(value)
    }
}
