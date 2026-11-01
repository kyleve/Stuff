import BroadwayCore

/// Typed inheritance runs before trait slicing. Reflection checks completeness only, never styling.
protocol WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self
}

extension WhereThemePatch {
    func requireComplete(path: String) throws {
        for child in Mirror(reflecting: self).children {
            let wrapped = child.value as? any WhereThemeBox
            let label = child.label ?? "value"
            let fieldPath = path + "." + (wrapped == nil ? label : String(label.dropFirst()))
            let field = wrapped?.themeValue ?? child.value
            let mirror = Mirror(reflecting: field)
            if mirror.displayStyle == .optional {
                guard let value = mirror.children.first?.value else {
                    throw WhereThemeValidationError(
                        path: fieldPath,
                        reason: "A root theme must define this value",
                    )
                }
                try WhereThemeCompleteness.check(value, path: fieldPath)
            } else {
                try WhereThemeCompleteness.check(field, path: fieldPath)
            }
        }
    }
}

private protocol WhereThemeBox {
    var themeValue: Any { get }
}

extension CopyOnWrite: WhereThemeBox {
    fileprivate var themeValue: Any {
        wrappedValue
    }
}

private enum WhereThemeCompleteness {
    static func check(_ value: Any, path: String) throws {
        if let patch = value as? any WhereThemePatch {
            try patch.requireComplete(path: path)
            return
        }
        // Wrapper enums carry patches; ordinary portable values may have legitimate nil fields.
        for child in Mirror(reflecting: value).children {
            try check(child.value, path: path + "." + (child.label ?? "value"))
        }
    }
}

func inheritPatch<Value: WhereThemePatch>(_ value: Value?, from parent: Value?) -> Value? {
    value?.inheriting(parent) ?? parent
}

func inheritOptionalPatch<Value: Codable & Hashable & Sendable & WhereThemePatch>(
    _ value: WhereThemeOptional<Value>?,
    from parent: WhereThemeOptional<Value>?,
) -> WhereThemeOptional<Value>? {
    guard let value else { return parent }
    switch value {
        case .clear: return .clear
        case let .value(patch):
            if case let .value(inherited) = parent { return .value(patch.inheriting(inherited)) }
            return .value(patch)
    }
}

func inheritModePatch<Value: Codable & Hashable & Sendable & WhereThemePatch>(
    _ value: BThemeValue<Value>?,
    from parent: BThemeValue<Value>?,
) -> BThemeValue<Value>? {
    guard let value else { return parent }
    let light = value.resolve(mode: .light).inheriting(parent?.resolve(mode: .light))
    let dark = value.resolve(mode: .dark).inheriting(parent?.resolve(mode: .dark))
    return light == dark ? .constant(light) : .modes(.init(light: light, dark: dark))
}
