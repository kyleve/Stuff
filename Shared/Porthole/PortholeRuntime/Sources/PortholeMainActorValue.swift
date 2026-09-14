/// Holds a non-Sendable value on MainActor while its scoped reference crosses the registry actor.
/// Generated adapters create and unwrap this box only on MainActor.
@MainActor
public final class PortholeMainActorValue<Value> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}
