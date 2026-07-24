import Foundation

/// The wire protocol version both ends exchange in the hello handshake. Bump on
/// any breaking change to the message shapes.
public let portholeProtocolVersion = 1

// MARK: - Hello

public struct HelloRequest: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var clientName: String

    public init(protocolVersion: Int = portholeProtocolVersion, clientName: String) {
        self.protocolVersion = protocolVersion
        self.clientName = clientName
    }
}

public struct HelloReply: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var appName: String
    public var bundleID: String
    public var deviceName: String

    public init(
        protocolVersion: Int = portholeProtocolVersion,
        appName: String,
        bundleID: String,
        deviceName: String,
    ) {
        self.protocolVersion = protocolVersion
        self.appName = appName
        self.bundleID = bundleID
        self.deviceName = deviceName
    }
}

// MARK: - Errors

/// Why a pairing attempt failed, distinct from other protocol errors so the UI
/// can react precisely (re-prompt vs. give up).
public enum PairingFailureReason: String, Codable, Sendable, Equatable {
    case wrongCode
    case expired
    case tooManyAttempts
}

/// Every failure the protocol can report. Codable so it rides the wire in a
/// `.failure` response; `Equatable` for test assertions.
public enum PortholeError: Error, Codable, Sendable, Equatable {
    case protocolMismatch(theirs: Int, ours: Int)
    case connectorNotFound(PortholeConnectorID)
    case actionNotFound(PortholeActionRef)
    case sourceNotFound(PortholeDataSourceRef)
    case invalidParameters(String)
    case subscriptionNotSupported(PortholeDataSourceRef)
    case handlerFailed(String)
    case notPaired
    case pairingFailed(PairingFailureReason)
    case frameTooLarge(Int)
}

extension PortholeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case let .protocolMismatch(theirs, ours):
                "Protocol mismatch: peer speaks v\(theirs), this build speaks v\(ours)."
            case let .connectorNotFound(id):
                "No connector with id `\(id)`."
            case let .actionNotFound(ref):
                "No action `\(ref)`."
            case let .sourceNotFound(ref):
                "No data source `\(ref)`."
            case let .invalidParameters(message):
                "Invalid parameters: \(message)"
            case let .subscriptionNotSupported(ref):
                "Data source `\(ref)` does not support subscriptions."
            case let .handlerFailed(message):
                "The connector handler failed: \(message)"
            case .notPaired:
                "This client is not paired with the device."
            case let .pairingFailed(reason):
                "Pairing failed: \(reason.rawValue)."
            case let .frameTooLarge(byteCount):
                "A message frame of \(byteCount) bytes exceeds the maximum."
        }
    }
}

// MARK: - Requests

/// A client → device request. Synthesized `Codable` (a keyed enum shape) — both
/// ends share this module, so the exact JSON keys are internal to the protocol.
public enum PortholeRequest: Codable, Sendable, Equatable {
    case hello(HelloRequest)
    case listConnectors
    case invokeAction(ref: PortholeActionRef, parameters: PortholeValue)
    case query(ref: PortholeDataSourceRef, query: PortholeQuery)
    case subscribe(ref: PortholeDataSourceRef)
    case unsubscribe(subscriptionID: UInt64)
    case ping
}

/// Wraps a request with the id the matching response echoes back.
public struct PortholeRequestEnvelope: Codable, Sendable, Equatable {
    public var id: UInt64
    public var request: PortholeRequest

    public init(id: UInt64, request: PortholeRequest) {
        self.id = id
        self.request = request
    }
}

// MARK: - Responses

/// A device → client response. `.event` is the only unsolicited case (its
/// envelope carries a nil `requestID`); everything else answers a request.
public enum PortholeResponse: Codable, Sendable, Equatable {
    case helloReply(HelloReply)
    case connectors([ConnectorManifest])
    case actionResult(PortholeValue)
    case queryResult(PortholePage)
    case subscribed(subscriptionID: UInt64)
    case event(subscriptionID: UInt64, value: PortholeValue)
    case failure(PortholeError)
    case pong
}

/// Wraps a response with the request id it answers (nil for unsolicited
/// `.event` frames).
public struct PortholeResponseEnvelope: Codable, Sendable, Equatable {
    public var requestID: UInt64?
    public var response: PortholeResponse

    public init(requestID: UInt64?, response: PortholeResponse) {
        self.requestID = requestID
        self.response = response
    }
}
