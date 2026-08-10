import Foundation

public struct XCResultSummary: Decodable, Equatable, Sendable {
    public let failedTests: Int?
    public let passedTests: Int?

    public init(failedTests: Int?, passedTests: Int?) {
        self.failedTests = failedTests
        self.passedTests = passedTests
    }
}

public enum XCResultToolFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case commandFailed(path: URL, detail: String)

    public var description: String {
        switch self {
            case let .commandFailed(path, detail):
                "xcresulttool could not inspect \(path.path): \(detail)"
        }
    }
}

/// Typed access to the stable JSON surfaces exported by `xcresulttool`.
public struct XCResultTool: Sendable {
    private let runner: any CommandRunning
    private let repository: URL

    public init(runner: any CommandRunning, repository: URL) {
        self.runner = runner
        self.repository = repository
    }

    public func testsData(at resultBundle: URL) async throws -> Data {
        try await data(section: "tests", at: resultBundle)
    }

    public func summaryData(at resultBundle: URL) async throws -> Data {
        try await data(section: "summary", at: resultBundle)
    }

    public func testCatalog(at resultBundle: URL) async throws -> XCResultTestCatalog {
        let data = try await testsData(at: resultBundle)
        return try JSONDecoder().decode(
            XCResultTestCatalog.self,
            from: data,
        )
    }

    public func summary(at resultBundle: URL) async throws -> XCResultSummary {
        let data = try await summaryData(at: resultBundle)
        return try JSONDecoder().decode(
            XCResultSummary.self,
            from: data,
        )
    }

    private func data(section: String, at resultBundle: URL) async throws -> Data {
        let result = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: [
                    "xcresulttool",
                    "get",
                    "test-results",
                    section,
                    "--path",
                    resultBundle.path,
                ],
                workingDirectory: repository,
            ),
        )
        guard result.succeeded else {
            throw XCResultToolFailure.commandFailed(
                path: resultBundle,
                detail: result.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines),
            )
        }
        return Data(result.standardOutput)
    }
}
