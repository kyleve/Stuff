import Foundation

public enum TestScope: Equatable, Sendable {
    case changed
    case all
    case snapshots
    case everything
    case bundles
    case only
}

public struct TestSchemePlan: Equatable, Sendable {
    public let name: String
    public let filters: [String]

    public init(name: String, filters: [String]) {
        self.name = name
        self.filters = filters
    }
}

public enum TestRunPlanFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case filterFileSpansSchemes
    case unknownBundle(String)
    case nothingToRun

    public var description: String {
        switch self {
            case .filterFileSpansSchemes:
                "--only-file must contain identifiers for one test scheme"
            case let .unknownBundle(name): "no test bundle named \(name)"
            case .nothingToRun: "nothing to run (see ./test --help)"
        }
    }
}

public struct TestRunPlan: Equatable, Sendable {
    public let schemes: [TestSchemePlan]

    public var runsUnitTests: Bool {
        schemes.contains { $0.name == RepositoryGraph.unitScheme }
    }

    public init(
        scope: TestScope,
        bundles: [String],
        only: [String],
        graph: RepositoryGraph?,
    ) throws {
        var schemeFilters: [String: [String]] = [:]
        var schemeOrder: [String] = []

        func addScheme(_ name: String) {
            if schemeFilters[name] == nil {
                schemeFilters[name] = []
                schemeOrder.append(name)
            }
        }

        func addFilter(_ identifier: String, to scheme: String) {
            addScheme(scheme)
            let filter = "-only-testing:\(identifier)"
            if schemeFilters[scheme]?.contains(filter) == false {
                schemeFilters[scheme]?.append(filter)
            }
        }

        switch scope {
            case .all:
                addScheme(RepositoryGraph.unitScheme)
            case .snapshots:
                addScheme(RepositoryGraph.snapshotScheme)
            case .everything:
                addScheme(RepositoryGraph.unitScheme)
                addScheme(RepositoryGraph.snapshotScheme)
            case .bundles, .changed:
                guard let graph else { throw TestRunPlanFailure.nothingToRun }
                for bundle in bundles {
                    guard graph.allTestBundles.contains(bundle) else {
                        throw TestRunPlanFailure.unknownBundle(bundle)
                    }
                    let scheme = graph.snapshotBundles.contains(bundle)
                        ? RepositoryGraph.snapshotScheme
                        : RepositoryGraph.unitScheme
                    addFilter(bundle, to: scheme)
                }
            case .only:
                break
        }

        for identifier in only {
            let bundle = identifier.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            let scheme = graph?.snapshotBundles.contains(bundle) == true
                ? RepositoryGraph.snapshotScheme
                : RepositoryGraph.unitScheme
            addFilter(identifier, to: scheme)
        }

        schemes = schemeOrder.map { name in
            TestSchemePlan(name: name, filters: schemeFilters[name, default: []])
        }
        guard schemes.isEmpty == false else {
            throw TestRunPlanFailure.nothingToRun
        }
    }

    public func filtering(usingFile path: String) throws -> TestRunPlan {
        guard schemes.count == 1 else {
            throw TestRunPlanFailure.filterFileSpansSchemes
        }
        return TestRunPlan(schemes: [
            TestSchemePlan(
                name: schemes[0].name,
                filters: ["-only-testing", "@\(path)"],
            ),
        ])
    }

    private init(schemes: [TestSchemePlan]) {
        self.schemes = schemes
    }
}
