import Foundation

public struct XCResultNode: Decodable, Equatable, Sendable {
    public let nodeType: String
    public let name: String
    public let result: String?
    public let nodeIdentifier: String?
    public let durationInSeconds: Double?
    public let children: [XCResultNode]

    private enum CodingKeys: String, CodingKey {
        case nodeType
        case name
        case result
        case nodeIdentifier
        case durationInSeconds
        case children
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeType = try container.decode(String.self, forKey: .nodeType)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        result = try container.decodeIfPresent(String.self, forKey: .result)
        nodeIdentifier = try container.decodeIfPresent(String.self, forKey: .nodeIdentifier)
        durationInSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .durationInSeconds,
        )
        children = try container.decodeIfPresent([XCResultNode].self, forKey: .children) ?? []
    }
}

public struct XCResultTestCatalog: Decodable, Equatable, Sendable {
    public let testNodes: [XCResultNode]
}

public struct FailedTest: Equatable, Sendable {
    public let label: String
    public let rerunIdentifier: String

    public init(label: String, rerunIdentifier: String) {
        self.label = label
        self.rerunIdentifier = rerunIdentifier
    }
}

public struct XCResultTestCase: Equatable, Sendable {
    public let identifier: String
    public let bundle: String
    public let name: String
    public let result: String
    public let durationInSeconds: Double

    public init(
        identifier: String,
        bundle: String,
        name: String,
        result: String,
        durationInSeconds: Double,
    ) {
        self.identifier = identifier
        self.bundle = bundle
        self.name = name
        self.result = result
        self.durationInSeconds = durationInSeconds
    }
}

extension XCResultTestCatalog {
    public var failures: [FailedTest] {
        var failures: [FailedTest] = []
        for node in testNodes {
            collectFailures(node, bundle: "?", suite: "?", into: &failures)
        }
        return failures
    }

    public var testCases: [XCResultTestCase] {
        var cases: [XCResultTestCase] = []
        for node in testNodes {
            collectTestCases(node, bundle: "?", suites: [], into: &cases)
        }
        return cases
    }

    private func collectFailures(
        _ node: XCResultNode,
        bundle: String,
        suite: String,
        into failures: inout [FailedTest],
    ) {
        let currentBundle = node.nodeType == "Unit test bundle" ? node.name : bundle
        let currentSuite = node.nodeType == "Test Suite" ? node.name : suite
        if node.nodeType == "Test Case", node.result == "Failed" {
            failures.append(
                FailedTest(
                    label: "\(currentBundle)/\(currentSuite)/\(node.name)",
                    rerunIdentifier: "\(currentBundle)/\(currentSuite)",
                ),
            )
        }
        for child in node.children {
            collectFailures(
                child,
                bundle: currentBundle,
                suite: currentSuite,
                into: &failures,
            )
        }
    }

    private func collectTestCases(
        _ node: XCResultNode,
        bundle: String,
        suites: [String],
        into cases: inout [XCResultTestCase],
    ) {
        let currentBundle = node.nodeType == "Unit test bundle" ? node.name : bundle
        let currentSuites = node.nodeType == "Test Suite" ? suites + [node.name] : suites
        if node.nodeType == "Test Case" {
            let fallback = (currentSuites + [node.name]).filter { $0.isEmpty == false }
                .joined(separator: "/")
            let nodeIdentifier = node.nodeIdentifier ?? fallback
            let identifier = currentBundle == "?" || nodeIdentifier.hasPrefix(currentBundle + "/")
                ? nodeIdentifier
                : "\(currentBundle)/\(nodeIdentifier)"
            cases.append(
                XCResultTestCase(
                    identifier: identifier,
                    bundle: currentBundle,
                    name: node.name,
                    result: node.result ?? "",
                    durationInSeconds: node.durationInSeconds ?? 0,
                ),
            )
        }
        for child in node.children {
            collectTestCases(
                child,
                bundle: currentBundle,
                suites: currentSuites,
                into: &cases,
            )
        }
    }
}
