import Foundation

public enum RepositoryGraphFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case missingScheme(String)
    case missingTarget(String)
    case emptyTestCatalog

    public var description: String {
        switch self {
            case let .missingScheme(name):
                "Tuist graph contains no \(name) scheme"
            case let .missingTarget(name):
                "Tuist graph scheme references unknown target \(name)"
            case .emptyTestCatalog:
                "Tuist graph contains no iOS test bundles"
        }
    }
}

/// The package and Tuist target graph used to choose safe affected test bundles.
public struct RepositoryGraph: Equatable, Sendable {
    public static let unitScheme = "Stuff-iOS-Tests"
    public static let snapshotScheme = "StuffSnapshotTests"

    private struct PackageTarget: Equatable {
        let sourceRoot: String
        let dependencies: Set<String>
    }

    private struct TuistTarget: Equatable {
        let sourceRoot: String?
        let targetDependencies: Set<String>
        let packageProducts: Set<String>
    }

    private struct Bundle: Equatable {
        let sourceRoot: String
        let reachableTuistTargets: Set<String>
        let reachablePackageTargets: Set<String>
    }

    private let packageTargets: [String: PackageTarget]
    private let tuistTargets: [String: TuistTarget]
    private let bundles: [String: Bundle]
    public let unitBundles: Set<String>
    public let snapshotBundles: Set<String>

    public init(
        tuistGraphData: Data,
        packageDumpData: Data,
        repository: URL,
    ) throws {
        let decoder = JSONDecoder()
        let tuist = try decoder.decode(TuistGraphDTO.self, from: tuistGraphData)
        let package = try decoder.decode(PackageDumpDTO.self, from: packageDumpData)
        let rootProject = tuist.projects.values[repository.standardizedFileURL.path]
        guard let project = rootProject ?? tuist.projects.values.values.first(where: { project in
            let schemeNames = Set(project.schemes.map(\.name))
            return schemeNames.contains(Self.unitScheme) ||
                schemeNames.contains(Self.snapshotScheme)
        }) else {
            throw RepositoryGraphFailure.emptyTestCatalog
        }

        let packageProducts = Dictionary(
            uniqueKeysWithValues: package.products.map { ($0.name, Set($0.targets)) },
        )
        var decodedPackageTargets: [String: PackageTarget] = [:]
        for target in package.targets {
            let dependencies = target.dependencies
                .reduce(into: Set<String>()) { result, dependency in
                    switch dependency {
                        case let .target(name):
                            result.insert(name)
                        case let .product(name):
                            result.formUnion(packageProducts[name, default: []])
                    }
                }
            decodedPackageTargets[target.name] = PackageTarget(
                sourceRoot: target.path ?? target.name,
                dependencies: dependencies,
            )
        }
        packageTargets = decodedPackageTargets

        var decodedTuistTargets: [String: TuistTarget] = [:]
        for (name, target) in project.targets {
            let sources = target.sources.map(\.path).map {
                Self.relativePath($0, repository: repository)
            }
            decodedTuistTargets[name] = TuistTarget(
                sourceRoot: Self.commonSourceRoot(sources),
                targetDependencies: Set(target.dependencies.compactMap(\.targetName)),
                packageProducts: Set(target.dependencies.compactMap(\.packageProduct)),
            )
        }
        tuistTargets = decodedTuistTargets

        func schemeBundles(_ name: String) throws -> Set<String> {
            guard let scheme = project.schemes.first(where: { $0.name == name }) else {
                throw RepositoryGraphFailure.missingScheme(name)
            }
            return Set(scheme.testAction?.targets.map(\.target.name) ?? [])
        }
        unitBundles = try schemeBundles(Self.unitScheme)
        snapshotBundles = try schemeBundles(Self.snapshotScheme)
        let allBundles = unitBundles.union(snapshotBundles)
        guard allBundles.isEmpty == false else {
            throw RepositoryGraphFailure.emptyTestCatalog
        }

        var decodedBundles: [String: Bundle] = [:]
        for name in allBundles {
            guard let target = decodedTuistTargets[name], let sourceRoot = target.sourceRoot else {
                throw RepositoryGraphFailure.missingTarget(name)
            }
            let tuistClosure = Self.transitiveClosure(from: [name]) { targetName in
                decodedTuistTargets[targetName]?.targetDependencies ?? []
            }
            let products = tuistClosure.reduce(into: Set<String>()) { result, targetName in
                result.formUnion(decodedTuistTargets[targetName]?.packageProducts ?? [])
            }
            let packageRoots = products.reduce(into: Set<String>()) { result, product in
                result.formUnion(packageProducts[product, default: []])
            }
            let packageClosure = Self.transitiveClosure(from: packageRoots) { targetName in
                decodedPackageTargets[targetName]?.dependencies ?? []
            }
            decodedBundles[name] = Bundle(
                sourceRoot: sourceRoot,
                reachableTuistTargets: tuistClosure,
                reachablePackageTargets: packageClosure,
            )
        }
        bundles = decodedBundles
    }

    public var allTestBundles: Set<String> {
        unitBundles.union(snapshotBundles)
    }

    public func affectedBundles(changedPaths: [String]) -> [String] {
        guard changedPaths.isEmpty == false else { return [] }
        if changedPaths.contains(where: isGlobalPath) {
            return allTestBundles.sorted()
        }

        var selected: Set<String> = []
        for path in changedPaths {
            if let bundle = bestOwner(
                for: path,
                candidates: bundles.mapValues(\.sourceRoot),
            ) {
                selected.insert(bundle)
                continue
            }
            if let target = bestOwner(
                for: path,
                candidates: packageTargets.mapValues(\.sourceRoot),
            ) {
                for (bundleName, bundle) in bundles
                    where bundle.reachablePackageTargets.contains(target)
                {
                    selected.insert(bundleName)
                }
                continue
            }
            let sourceRoots = tuistTargets.compactMapValues(\.sourceRoot)
            if let target = bestOwner(for: path, candidates: sourceRoots) {
                for (bundleName, bundle) in bundles
                    where bundle.reachableTuistTargets.contains(target)
                {
                    selected.insert(bundleName)
                }
                continue
            }

            let module = path.split(separator: "/").prefix(2).joined(separator: "/")
            for (bundleName, bundle) in bundles
                where bundle.sourceRoot == module || bundle.sourceRoot.hasPrefix(module + "/")
            {
                selected.insert(bundleName)
            }
        }
        return selected.sorted()
    }

    private func bestOwner(
        for path: String,
        candidates: [String: String],
    ) -> String? {
        candidates
            .filter { _, root in path == root || path.hasPrefix(root + "/") }
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private func isGlobalPath(_ path: String) -> Bool {
        let exact: Set = [
            "Package.swift",
            "Package.resolved",
            "Project.swift",
            "Tuist.swift",
            ".swiftformat",
            ".mise.toml",
            "test",
            "simulator",
            "ide",
            "Tools/Package.swift",
            "Tools/Package.resolved",
        ]
        return exact.contains(path) || path.hasPrefix(".github/") || path
            .hasPrefix("Tools/")
    }

    private static func relativePath(_ path: String, repository: URL) -> String {
        let root = repository.standardizedFileURL.path + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    private static func commonSourceRoot(_ sources: [String]) -> String? {
        guard var components = sources.first?.split(separator: "/").dropLast().map(String.init)
        else {
            return nil
        }
        for source in sources.dropFirst() {
            let candidate = source.split(separator: "/").dropLast().map(String.init)
            components = Array(
                zip(components, candidate)
                    .prefix { $0 == $1 }
                    .map(\.0),
            )
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }

    private static func transitiveClosure(
        from roots: Set<String>,
        dependencies: (String) -> Set<String>,
    ) -> Set<String> {
        var found = roots
        var frontier = Array(roots)
        while let next = frontier.popLast() {
            for dependency in dependencies(next) where found.insert(dependency).inserted {
                frontier.append(dependency)
            }
        }
        return found
    }
}

private struct AlternatingDictionary<Value: Decodable>: Decodable {
    let values: [String: Value]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [String: Value] = [:]
        while container.isAtEnd == false {
            let key = try container.decode(String.self)
            values[key] = try container.decode(Value.self)
        }
        self.values = values
    }
}

private struct TuistGraphDTO: Decodable {
    let projects: AlternatingDictionary<TuistProjectDTO>
}

private struct TuistProjectDTO: Decodable {
    let schemes: [TuistSchemeDTO]
    let targets: [String: TuistTargetDTO]
}

private struct TuistSchemeDTO: Decodable {
    struct TestAction: Decodable {
        struct TestTarget: Decodable {
            struct Target: Decodable {
                let name: String
            }

            let target: Target
        }

        let targets: [TestTarget]
    }

    let name: String
    let testAction: TestAction?
}

private struct TuistTargetDTO: Decodable {
    struct Source: Decodable {
        let path: String
    }

    let dependencies: [TuistDependencyDTO]
    let sources: [Source]
}

private struct TuistDependencyDTO: Decodable {
    struct Package: Decodable {
        let product: String
    }

    struct Target: Decodable {
        let name: String
    }

    let package: Package?
    let target: Target?

    var packageProduct: String? {
        package?.product
    }

    var targetName: String? {
        target?.name
    }
}

private struct PackageDumpDTO: Decodable {
    struct Product: Decodable {
        let name: String
        let targets: [String]
    }

    struct Target: Decodable {
        let name: String
        let path: String?
        let dependencies: [PackageDependencyDTO]
    }

    let products: [Product]
    let targets: [Target]
}

private enum PackageDependencyDTO: Decodable {
    case target(String)
    case product(String)

    private enum CodingKeys: String, CodingKey {
        case byName
        case target
        case product
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try container.decodeIfPresent([String?].self, forKey: .target),
           let name = values.first ?? nil
        {
            self = .target(name)
        } else if let values = try container.decodeIfPresent([String?].self, forKey: .byName),
                  let name = values.first ?? nil
        {
            self = .target(name)
        } else {
            let values = try container.decode([String?].self, forKey: .product)
            guard let name = values.first ?? nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .product,
                    in: container,
                    debugDescription: "package dependency has no name",
                )
            }
            self = .product(name)
        }
    }
}
