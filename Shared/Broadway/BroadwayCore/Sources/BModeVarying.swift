/// A pair of authored values selected with the stylesheet slice's explicit mode.
public struct BModeVarying<Value> {
    public let light: Value
    public let dark: Value

    public init(light: Value, dark: Value) {
        self.light = light
        self.dark = dark
    }

    public subscript(mode: BMode) -> Value {
        switch mode {
            case .light: light
            case .dark: dark
        }
    }
}

extension BModeVarying: Equatable where Value: Equatable {}
extension BModeVarying: Hashable where Value: Hashable {}
extension BModeVarying: Sendable where Value: Sendable {}

extension BModeVarying: Codable where Value: Codable {}
