import PortholeCore

/// The host captures this origin before any debugger surface appears.
public enum PortholePresentationOrigin: Sendable, Equatable {
    case screen(PortholeContext)
    case application(PortholeScopeToken)

    public var scope: PortholeScopeToken {
        switch self {
            case let .screen(context): context.scope
            case let .application(scope): scope
        }
    }
}
