/// The execution context that owns a capability's native implementation.
public enum PortholeExecutionOwnership: Sendable, Equatable, Codable {
    case unisolated
    case mainActor
    case actorInstance(typeName: String)
    case adapter
}
