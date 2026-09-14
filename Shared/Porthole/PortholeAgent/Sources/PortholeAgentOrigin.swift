import Foundation
import PortholeCore

/// The original capture stays with an investigation when the live application changes.
public enum PortholeAgentOrigin: Sendable, Equatable, Codable {
    case screen(context: PortholeContext)
    case application(scope: PortholeScopeToken)

    // swiftformat:disable redundantRawValues
    private enum CodingKeys: String,
        CodingKey { case screen = "screen", application = "application" }
    private enum ScreenCodingKeys: String, CodingKey { case context = "context" }
    private enum ApplicationCodingKeys: String, CodingKey { case scope = "scope" }
    // swiftformat:enable redundantRawValues

    public var title: String {
        switch self { case let .screen(context): context.title; case .application: "Application" }
    }

    public var scope: PortholeScopeToken {
        switch self { case let .screen(context): context.scope; case let .application(scope): scope
        }
    }
}

public struct PortholeAgentModelIdentity: Sendable, Equatable, Codable {
    public let provider: PortholeAgentProvider
    public let modelID: String
    public init(provider: PortholeAgentProvider, modelID: String) {
        self.provider = provider; self.modelID = modelID
    }
}

public struct PortholeAgentRunIdentity: Sendable, Equatable, Codable {
    public let runID: UUID
    public let model: PortholeAgentModelIdentity
    public let startedAt: Date
}

/// An explicit user action changes live scope without rewriting earlier evidence.
public struct PortholeAgentContextChange: Sendable, Equatable, Codable {
    public let origin: PortholeAgentOrigin
    public let provenance: PortholeValue
    public let adoptedAt: Date
}
