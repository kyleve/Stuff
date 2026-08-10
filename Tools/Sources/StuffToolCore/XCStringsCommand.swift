import ArgumentParser
import Foundation

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

    public mutating func run() throws {
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true,
        )
        let repository = ProcessInfo.processInfo.environment["STUFF_REPOSITORY_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? workingDirectory
        let normalizer = StringCatalogNormalizer()
        let targets = try paths.isEmpty
            ? normalizer.catalogs(under: repository)
            : paths
            .map { URL(fileURLWithPath: $0, relativeTo: workingDirectory).standardizedFileURL }
        let offenders = try normalizer.normalize(targets, lintOnly: lint) { print($0) }

        if offenders.isEmpty {
            let subject = targets.count == 1 ? "catalog already matches" : "catalogs already match"
            print("\(targets.count) \(subject) Xcode's serialization.")
        } else if lint {
            let subject = offenders.count == 1 ? "catalog isn't" : "catalogs aren't"
            FileHandle.standardError.write(
                Data("\(offenders.count) \(subject) normalized — run ./xcstrings\n".utf8),
            )
            throw ExitCode.failure
        }
    }
}

/// Discovers and normalizes String Catalogs without owning command-line I/O.
public struct StringCatalogNormalizer: Sendable {
    public init() {}

    public func normalized(_ url: URL) throws -> Data {
        let original = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: original)
        let rewritten = try CatalogSerializer().data(from: object)
        let reparsed = try JSONSerialization.jsonObject(with: rewritten)
        guard NSDictionary(dictionary: object as? [String: Any] ?? [:])
            .isEqual(to: reparsed as? [String: Any] ?? [:])
        else {
            throw CatalogSerializer.Failure.unsupportedValue(
                "\(type(of: object)) (\(object))",
            )
        }
        return rewritten
    }

    public func catalogs(under root: URL) throws -> [URL] {
        let skipped: Set = ["Derived", ".build", ".git", "build"]
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true,
               skipped.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj"
            {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcstrings" {
                found.append(url)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    @discardableResult
    public func normalize(
        _ targets: [URL],
        lintOnly: Bool,
        report: (String) -> Void,
    ) throws -> [URL] {
        var offenders: [URL] = []
        let root = FileManager.default.currentDirectoryPath + "/"
        for url in targets {
            let rewritten = try normalized(url)
            guard try rewritten != Data(contentsOf: url) else { continue }
            offenders.append(url)
            let display = url.path.replacingOccurrences(of: root, with: "")
            if lintOnly {
                report("not normalized: \(display)")
            } else {
                try rewritten.write(to: url, options: .atomic)
                report("normalized: \(display)")
            }
        }
        return offenders
    }
}
