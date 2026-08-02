import Foundation

/// Strip any nesting of `Optional` from a reflected value, yielding the inner
/// value or `nil` when it bottoms out at `.none`.
enum InspectorOptionalUnwrapping {
    static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let child = mirror.children.first else { return nil }
        return unwrap(child.value)
    }
}
