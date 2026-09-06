import PeriscopeCore

/// A sendable error attachment retained until Throw's durable log store is ready.
public struct ThrowSoftwareCreditsLoadFailure: Equatable, Sendable {
    let attachment: LogAttachment

    public init(error: any Error) {
        attachment = .error(error, name: "attribution-error")
    }
}
