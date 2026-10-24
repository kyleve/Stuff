import PeriscopeCore

/// A classified error snapshot and attachment retained until Throw's durable log store is ready.
public struct ThrowSoftwareCreditsLoadFailure: Equatable, Sendable {
    let error: LogError
    let attachment: LogAttachment

    public init(error: any Error) {
        self.error = LogError(capturing: error)
        attachment = .error(error, name: "attribution-error")
    }
}
