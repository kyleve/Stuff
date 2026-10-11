#if DEBUG
    /// Session-only Flyover identity derived from the represented screen type.
    struct WhereFlyoverScreenID: Hashable, CustomStringConvertible {
        private let value: Value
        private let typeName: String

        init(_ screenType: Any.Type) {
            value = .screen(ObjectIdentifier(screenType))
            typeName = String(reflecting: screenType)
        }

        init(_ screenType: Any.Type, in contextType: Any.Type) {
            value = .contextual(
                screen: ObjectIdentifier(screenType),
                context: ObjectIdentifier(contextType),
            )
            typeName = "\(String(reflecting: screenType)) in \(String(reflecting: contextType))"
        }

        var description: String {
            typeName
        }

        var exportIdentifier: String {
            typeName
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(value)
        }

        private enum Value: Hashable {
            case screen(ObjectIdentifier)
            case contextual(screen: ObjectIdentifier, context: ObjectIdentifier)
        }
    }
#endif
