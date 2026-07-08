import Foundation

/// Identifies one live object instance: its pointer identity *plus* its
/// dynamic type, so a recycled pointer from a deallocated object of another
/// type can never be mistaken for the original — and debug output names the
/// type instead of showing a bare address.
public struct InstanceID: Hashable, Sendable, CustomDebugStringConvertible {
    /// Pointer identity of the instance.
    let object: ObjectIdentifier

    /// Identity of the instance's dynamic type.
    let typeID: ObjectIdentifier

    /// The dynamic type's name, e.g. `"PhotoController"`.
    public let typeName: String

    public init(of instance: AnyObject) {
        object = ObjectIdentifier(instance)
        let dynamicType = type(of: instance)
        typeID = ObjectIdentifier(dynamicType)
        typeName = String(describing: dynamicType)
    }

    public var debugDescription: String {
        "\(typeName)@0x\(String(UInt(bitPattern: object), radix: 16))"
    }

    public static func == (lhs: InstanceID, rhs: InstanceID) -> Bool {
        lhs.object == rhs.object && lhs.typeID == rhs.typeID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(object)
        hasher.combine(typeID)
    }
}
