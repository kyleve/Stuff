import ArgumentParser
import Foundation

public struct XCStringsRequest: Equatable, Sendable {
    public let lint: Bool
    public let paths: [String]

    public init(lint: Bool, paths: [String]) {
        self.lint = lint
        self.paths = paths
    }
}

public struct XCStringsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "xcstrings",
        abstract: "Rewrite String Catalogs using Xcode's serialization.",
        discussion: """
        With no paths, walks the repository for every .xcstrings catalog. This
        changes formatting only; it never adds, removes, or edits catalog entries.
        """,
    )

    @Flag(help: "Report catalogs that are not normalized; write nothing.")
    var lint = false

    @Argument(help: "Catalogs to process.")
    var paths: [String] = []

    public init() {}

    public func makeRequest() -> XCStringsRequest {
        XCStringsRequest(lint: lint, paths: paths)
    }

    public mutating func run() throws {
        let request = makeRequest()
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true,
        )
        let repository = ProcessInfo.processInfo.environment["STUFF_REPOSITORY_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? workingDirectory
        let normalizer = StringCatalogNormalizer()
        let targets = try request.paths.isEmpty
            ? normalizer.catalogs(under: repository)
            : request.paths
            .map { URL(fileURLWithPath: $0, relativeTo: workingDirectory).standardizedFileURL }
        let offenders = try normalizer.normalize(targets, lintOnly: request.lint) { print($0) }

        if offenders.isEmpty {
            let subject = targets.count == 1 ? "catalog already matches" : "catalogs already match"
            print("\(targets.count) \(subject) Xcode's serialization.")
        } else if request.lint {
            let subject = offenders.count == 1 ? "catalog isn't" : "catalogs aren't"
            FileHandle.standardError.write(
                Data("\(offenders.count) \(subject) normalized — run ./xcstrings\n".utf8),
            )
            throw ExitCode.failure
        }
    }
}
