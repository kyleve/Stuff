import CodeGraphModel
import Foundation
import IndexStoreDB

/// Walks an opened index store and assembles a ``CodeGraph``.
///
/// Two passes over the repo's first-party source files:
///   1. definitions become nodes, and their relations become the structural
///      edges (inheritance, conformance, override, membership);
///   2. references become the data-flow edges (property / parameter / return
///      types, construction, generic constraints).
/// External symbols the repo touches are synthesized as leaf nodes on demand.
final class GraphBuilder {
    private let db: IndexStoreDB
    private let repoPath: String
    private let repoPrefix: String

    private var nodes: [String: Node] = [:]
    private var edges: [String: Edge] = [:]
    private var moduleNameCache: [String: String] = [:]
    private var constructorParentCache: [String: Symbol?] = [:]

    init(db: IndexStoreDB, repoPath: String) {
        self.db = db
        self.repoPath = repoPath
        repoPrefix = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
    }

    func build() -> (modules: [Module], nodes: [Node], edges: [Edge]) {
        let files = firstPartySwiftFiles()
        for file in files {
            harvestDefinitions(in: file)
        }
        for file in files {
            harvestReferences(in: file)
        }
        let modules = finalize()
        return (modules, Array(nodes.values), Array(edges.values))
    }

    // MARK: - Pass A: definitions

    private func harvestDefinitions(in file: String) {
        for occ in db.symbolOccurrences(inFilePath: file) {
            guard occ.roles.contains(.definition) else { continue }
            let origin = SymbolMapping.origin(
                path: occ.location.path,
                isSystem: occ.location.isSystem,
                repoPrefix: repoPrefix,
            )
            guard origin != .external else { continue }
            guard !occ.symbol.properties.contains(.local) else { continue }
            guard let kind = SymbolMapping.nodeKind(for: occ.symbol) else { continue }

            nodes[occ.symbol.usr] = makeNode(occ: occ, kind: kind, origin: origin)
            addStructuralEdges(from: occ)
            addInheritanceEdges(from: occ)
        }
    }

    private func makeNode(occ: SymbolOccurrence, kind: NodeKind, origin: Origin) -> Node {
        let module = occ.location.moduleName.isEmpty ? "Unknown" : occ.location.moduleName
        return Node(
            id: occ.symbol.usr,
            name: occ.symbol.name,
            kind: kind,
            module: module,
            origin: origin,
            parentID: parentUSR(of: occ) ?? moduleNodeID(module),
            file: relativePath(occ.location.path),
            line: occ.location.line,
            isGeneric: occ.symbol.properties.contains(.generic),
        )
    }

    /// Override and membership edges, which the index records on the child /
    /// overriding declaration's own occurrence.
    private func addStructuralEdges(from occ: SymbolOccurrence) {
        let source = occ.symbol.usr
        for relation in occ.relations {
            let related = relation.symbol
            if relation.roles.contains(.overrideOf) {
                ensureLeafNode(for: related)
                insert(source: source, target: related.usr, kind: .override)
            }
            if relation.roles.contains(.childOf) {
                // Parent owns this symbol; emit the membership edge parent -> child.
                insert(source: related.usr, target: source, kind: .member)
            }
        }
    }

    /// Inheritance and conformance edges. Swift records these at the *base*
    /// type's reference in the inheritance clause: the occurrence's symbol is
    /// the base, and a `.baseOf` relation points to the derived type. Returns
    /// whether any such edge was found (so the reference pass can skip treating
    /// the same occurrence as a data-flow reference).
    @discardableResult
    private func addInheritanceEdges(from occ: SymbolOccurrence) -> Bool {
        let base = occ.symbol
        var found = false
        for relation in occ.relations where relation.roles.contains(.baseOf) {
            let derived = relation.symbol
            // Only a class base is true subclassing; protocol bases and
            // raw-value bases (e.g. `enum E: String`) are conformances.
            let kind: EdgeKind = base.kind == .class ? .inheritance : .conformance
            ensureLeafNode(for: base)
            ensureLeafNode(for: derived)
            insert(source: derived.usr, target: base.usr, kind: kind)
            found = true
        }
        return found
    }

    // MARK: - Pass B: references (data flow)

    private func harvestReferences(in file: String) {
        for occ in db.symbolOccurrences(inFilePath: file) {
            guard occ.roles.contains(.reference), !occ.roles.contains(.definition) else { continue }
            // Inheritance-clause references record conformance/inheritance; once
            // handled they should not also count as a data-flow reference.
            if addInheritanceEdges(from: occ) { continue }
            guard let container = container(of: occ) else { continue }
            guard let source = sourceInfo(forContainer: container) else { continue }
            guard let (target, kind) = classify(reference: occ, container: container)
            else { continue }
            guard source.id != target.usr else { continue }
            ensureLeafNode(for: target)
            insert(source: source.id, target: target.usr, kind: kind, viaMember: source.via)
        }
    }

    /// The declaration the reference textually sits inside.
    private func container(of occ: SymbolOccurrence) -> Symbol? {
        if let contained = occ.relations.first(where: { $0.roles.contains(.containedBy) }) {
            return contained.symbol
        }
        if let called = occ.relations.first(where: { $0.roles.contains(.calledBy) }) {
            return called.symbol
        }
        return nil
    }

    /// The graph node a reference should originate from: the owning type when
    /// the container is a member, otherwise the container itself.
    private func sourceInfo(forContainer container: Symbol) -> (id: String, via: String?)? {
        guard let node = nodes[container.usr] else { return nil }
        if node.kind.isMember {
            guard let parent = node.parentID else { return nil }
            return (parent, container.usr)
        }
        return (container.usr, nil)
    }

    private func classify(
        reference occ: SymbolOccurrence,
        container: Symbol,
    ) -> (target: Symbol, kind: EdgeKind)? {
        let referenced = occ.symbol
        if referenced.kind == .constructor {
            guard let type = constructorParent(referenced) else { return nil }
            return (type, .construction)
        }
        guard SymbolMapping.isType(referenced.kind) else { return nil }
        let kind: EdgeKind = switch container.kind {
            case .instanceProperty, .classProperty, .staticProperty, .variable, .field:
                .propertyType
            case .instanceMethod, .classMethod, .staticMethod, .function, .constructor,
                 .destructor, .conversionFunction:
                occ.roles.contains(.call) ? .construction : .paramOrReturnType
            case .class, .struct, .enum, .protocol, .extension, .union, .typealias:
                referenced.kind == .protocol ? .genericConstraint : .reference
            default:
                .reference
        }
        return (referenced, kind)
    }

    // MARK: - External leaves & lookups

    private func ensureLeafNode(for symbol: Symbol) {
        guard nodes[symbol.usr] == nil else { return }
        guard let kind = SymbolMapping.nodeKind(for: symbol) else { return }
        let module = externalModuleName(for: symbol)
        nodes[symbol.usr] = Node(
            id: symbol.usr,
            name: symbol.name,
            kind: kind,
            module: module,
            origin: .external,
            parentID: moduleNodeID(module),
            isGeneric: symbol.properties.contains(.generic),
        )
    }

    private func parentUSR(of occ: SymbolOccurrence) -> String? {
        occ.relations.first { $0.roles.contains(.childOf) }?.symbol.usr
    }

    private func constructorParent(_ constructor: Symbol) -> Symbol? {
        if let cached = constructorParentCache[constructor.usr] {
            return cached
        }
        var parent: Symbol?
        for occ in db.occurrences(ofUSR: constructor.usr, roles: [.definition, .declaration]) {
            if let rel = occ.relations.first(where: { $0.roles.contains(.childOf) }) {
                parent = rel.symbol
                break
            }
        }
        constructorParentCache[constructor.usr] = parent
        return parent
    }

    private func externalModuleName(for symbol: Symbol) -> String {
        if let cached = moduleNameCache[symbol.usr] {
            return cached
        }
        var module = "External"
        for occ in db.occurrences(ofUSR: symbol.usr, roles: [.definition, .declaration])
            where !occ.location.moduleName.isEmpty
        {
            module = occ.location.moduleName
            break
        }
        moduleNameCache[symbol.usr] = module
        return module
    }

    // MARK: - Finalize

    private func finalize() -> [Module] {
        ensureModuleNodes()
        repairParents()
        let dependencies = addModuleDependencyEdges()
        dropDanglingEdges()
        return makeModules(dependencies: dependencies)
    }

    private func ensureModuleNodes() {
        var origins: [String: Origin] = [:]
        for node in nodes.values where node.kind != .module {
            origins[node.module] = strongestOrigin(origins[node.module], node.origin)
        }
        for (module, origin) in origins {
            let id = moduleNodeID(module)
            guard nodes[id] == nil else { continue }
            nodes[id] = Node(id: id, name: module, kind: .module, module: module, origin: origin)
        }
    }

    private func repairParents() {
        for (id, node) in nodes {
            guard let parent = node.parentID, nodes[parent] == nil else { continue }
            var fixed = node
            fixed.parentID = moduleNodeID(node.module)
            nodes[id] = fixed
        }
    }

    /// Adds module-to-module edges for every observed cross-module relationship
    /// and returns, per module, the set of modules it depends on.
    private func addModuleDependencyEdges() -> [String: Set<String>] {
        var dependencies: [String: Set<String>] = [:]
        for edge in edges.values {
            guard
                let sourceModule = nodes[edge.source]?.module,
                let targetModule = nodes[edge.target]?.module,
                sourceModule != targetModule
            else { continue }
            dependencies[sourceModule, default: []].insert(targetModule)
        }
        for (source, targets) in dependencies {
            for target in targets {
                insert(
                    source: moduleNodeID(source),
                    target: moduleNodeID(target),
                    kind: .moduleDependency,
                )
            }
        }
        return dependencies
    }

    private func dropDanglingEdges() {
        edges = edges.filter { nodes[$0.value.source] != nil && nodes[$0.value.target] != nil }
    }

    private func makeModules(dependencies: [String: Set<String>]) -> [Module] {
        nodes.values
            .filter { $0.kind == .module }
            .map { node in
                Module(
                    name: node.name,
                    kind: moduleKind(name: node.name, origin: node.origin),
                    dependencies: (dependencies[node.name] ?? []).sorted(),
                )
            }
            .sorted { $0.name < $1.name }
    }

    private func moduleKind(name: String, origin: Origin) -> ModuleKind {
        switch origin {
            case .external: .external
            case .test: .test
            case .firstParty: name.hasSuffix("Tests") ? .test : .library
        }
    }

    // MARK: - Helpers

    private func insert(source: String, target: String, kind: EdgeKind, viaMember: String? = nil) {
        let key = "\(source)|\(target)|\(kind.rawValue)|\(viaMember ?? "")"
        if var existing = edges[key] {
            existing.count += 1
            edges[key] = existing
        } else {
            edges[key] = Edge(
                id: key,
                source: source,
                target: target,
                kind: kind,
                viaMemberID: viaMember,
            )
        }
    }

    private func moduleNodeID(_ module: String) -> String {
        "module:\(module)"
    }

    private func strongestOrigin(_ current: Origin?, _ candidate: Origin) -> Origin {
        guard let current else { return candidate }
        let rank: (Origin) -> Int = { origin in
            switch origin {
                case .firstParty: 2
                case .test: 1
                case .external: 0
            }
        }
        return rank(candidate) > rank(current) ? candidate : current
    }

    private func relativePath(_ path: String) -> String {
        path.hasPrefix(repoPrefix) ? String(path.dropFirst(repoPrefix.count)) : path
    }

    private func firstPartySwiftFiles() -> [String] {
        let excluded: Set = [".build", "Derived", "DerivedData", ".codegraph", ".git"]
        let root = URL(fileURLWithPath: repoPath)
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
            )
        else { return [] }

        var files: [String] = []
        for case let url as URL in enumerator {
            if excluded.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "swift" {
                files.append(url.path)
            }
        }
        return files
    }
}
