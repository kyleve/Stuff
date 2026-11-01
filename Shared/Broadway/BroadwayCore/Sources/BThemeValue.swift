/// A portable authored value, either constant or selected by the explicit slice mode.
public enum BThemeValue<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    case constant(Value)
    case modes(BModeVarying<Value>)

    public func resolve(mode: BMode) -> Value {
        switch self {
            case let .constant(value): value
            case let .modes(values): values[mode]
        }
    }
}
