import CodeGraphModel
import IndexStoreDB

/// Translates index-store symbol metadata into the graph's vocabulary.
enum SymbolMapping {
    /// Maps an index symbol to a graph node kind, or `nil` for kinds we never
    /// surface as nodes (parameters, accessors, generic type params, etc.).
    static func nodeKind(for symbol: Symbol) -> NodeKind? {
        switch symbol.kind {
            case .class:
                // Swift actors are indexed as classes; the index can't tell them
                // apart, so they surface as `.class` (a SwiftSyntax pass could
                // refine this later).
                .class
            case .struct:
                .struct
            case .enum:
                .enum
            case .protocol:
                .protocol
            case .extension:
                .extension
            case .union:
                .struct
            case .typealias:
                switch symbol.subKind {
                    case .swiftAssociatedType: .associatedType
                    case .swiftGenericTypeParam: nil
                    default: .typeAlias
                }
            case .function:
                .function
            case .instanceMethod, .classMethod, .staticMethod, .destructor, .conversionFunction:
                isAccessor(symbol.subKind) ? nil : .method
            case .constructor:
                .initializer
            case .instanceProperty, .classProperty, .staticProperty, .variable, .field:
                isAccessor(symbol.subKind) ? nil : .property
            case .enumConstant:
                .enumCase
            case .unknown, .module, .namespace, .namespaceAlias, .macro, .parameter, .using,
                 .concept, .commentTag:
                nil
        }
    }

    /// Whether the index symbol kind denotes a nominal type (the things a
    /// data-flow edge can point at).
    static func isType(_ kind: IndexSymbolKind) -> Bool {
        switch kind {
            case .class, .struct, .enum, .protocol, .extension, .typealias, .union:
                true
            case .unknown, .module, .namespace, .namespaceAlias, .macro, .function, .variable,
                 .field, .enumConstant, .instanceMethod, .classMethod, .staticMethod,
                 .instanceProperty, .classProperty, .staticProperty, .constructor, .destructor,
                 .conversionFunction, .parameter, .using, .concept, .commentTag:
                false
        }
    }

    /// Classifies where a declaration lives relative to the repository.
    static func origin(path: String, isSystem: Bool, repoPrefix: String) -> Origin {
        if isSystem || path.isEmpty {
            return .external
        }
        guard path.hasPrefix(repoPrefix) else {
            return .external
        }
        return path.contains("/Tests/") ? .test : .firstParty
    }

    private static func isAccessor(_ subKind: IndexSymbolSubKind) -> Bool {
        switch subKind {
            case .accessorGetter, .accessorSetter, .swiftAccessorWillSet, .swiftAccessorDidSet,
                 .swiftAccessorAddressor, .swiftAccessorMutableAddressor:
                true
            case .none, .cxxCopyConstructor, .cxxMoveConstructor, .swiftExtensionOfStruct,
                 .swiftExtensionOfClass, .swiftExtensionOfEnum, .swiftExtensionOfProtocol,
                 .swiftPrefixOperator, .swiftPostfixOperator, .swiftInfixOperator, .swiftSubscript,
                 .swiftAssociatedType, .swiftGenericTypeParam:
                false
        }
    }
}
