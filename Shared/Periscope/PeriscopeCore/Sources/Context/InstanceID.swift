import Foundation

/// Identifies one live object instance: its pointer identity *plus* its
/// dynamic type, so a recycled pointer from a deallocated object of another
/// type can never be mistaken for the original — and debug output names the
/// type instead of showing a bare address.
public struct InstanceID: Hashable, Sendable, CustomDebugStringConvertible {
    /// Pointer identity of the instance.
    let object: ObjectIdentifier

    /// The instance's dynamic type.
    public let type: Any.Type

    /// The dynamic type's name, e.g. `"PhotoController"` — derived on
    /// demand from ``type``.
    public var typeName: String {
        String(describing: type)
    }

    public init(of instance: AnyObject) {
        object = ObjectIdentifier(instance)
        type = Swift.type(of: instance)
    }

    public var debugDescription: String {
        "\(typeName)@0x\(String(UInt(bitPattern: object), radix: 16))"
    }

    public static func == (lhs: InstanceID, rhs: InstanceID) -> Bool {
        lhs.object == rhs.object && ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(object)
        hasher.combine(ObjectIdentifier(type))
    }
}
