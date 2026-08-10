import Foundation

public struct XCResultNode: Decodable, Equatable, Sendable {
    public let nodeType: String
    public let name: String
    public let result: String?
    public let children: [XCResultNode]

    private enum CodingKeys: String, CodingKey {
        case nodeType
        case name
        case result
        case children
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeType = try container.decode(String.self, forKey: .nodeType)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        result = try container.decodeIfPresent(String.self, forKey: .result)
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

extension XCResultTestCatalog {
    public var failures: [FailedTest] {
        var failures: [FailedTest] = []
        for node in testNodes {
            collectFailures(node, bundle: "?", suite: "?", into: &failures)
        }
        return failures
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
}
