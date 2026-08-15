import CryptoKit
import Foundation
import IndexStore
import SwiftParser
import SwiftSyntax

struct TestBundle: Codable, Hashable {
    let name: String
    let sourceRoot: String

    var scheme: String {
        name.hasSuffix("SnapshotTests") ? "StuffSnapshotTests" : "Stuff-iOS-Tests"
    }
}

struct TestSuite: Codable, Hashable {
    let bundle: String
    let name: String
    let sourcePath: String

    var identifier: String {
        "\(bundle)/\(name)"
    }
}

struct SelectionReason: Codable, Hashable {
    let path: String
    let reason: String
    let identifiers: [String]
}

struct SchemeSelection: Codable, Equatable {
    let scope: String
    let identifiers: [String]
}

struct TestImpactSelection: Codable, Equatable {
    static let formatVersion = 1

    let formatVersion: Int
    let base: String
    let head: String
    let fingerprint: String
    let fallback: Bool
    let schemes: [String: SchemeSelection]
    let reasons: [SelectionReason]
}

enum TestImpactError: Error, CustomStringConvertible {
    case invalidProject(String)
    case invalidArguments(String)
    case invalidIndex(String)
    case commandFailed([String], String)

    var description: String {
        switch self {
            case let .invalidProject(message), let .invalidArguments(message),
                 let .invalidIndex(message):
                message
            case let .commandFailed(command, message):
                "\(command.joined(separator: " ")) failed: \(message)"
        }
    }
}

struct CommandRunner {
    func output(_ command: [String], directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self,
        )
        let error = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self,
        )
        guard process.terminationStatus == 0 else {
            throw TestImpactError.commandFailed(
                command,
                error.trimmingCharacters(in: .whitespacesAndNewlines),
            )
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ProjectInventory {
    let bundles: [TestBundle]
    let suites: [TestSuite]
    let freeTestBundles: Set<String>

    init(repo: URL) throws {
        let projectURL = repo.appending(path: "Project.swift")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let declarationExpression = try NSRegularExpression(
            pattern: #"(?m)^ {8}(?:unitTests\(|\.target\()"#,
        )
        let fullRange = NSRange(project.startIndex..., in: project)
        let starts = declarationExpression.matches(in: project, range: fullRange)
            .map(\.range.location) + [
                project.utf16.count,
            ]
        var discovered: [TestBundle] = []
        for pair in zip(starts, starts.dropFirst()) {
            let range = NSRange(location: pair.0, length: pair.1 - pair.0)
            guard let swiftRange = Range(range, in: project) else { continue }
            let declaration = String(project[swiftRange])
            guard
                let name = Self.firstCapture(#"name:\s*\"(\w+)\""#, in: declaration),
                name.hasSuffix("Tests"),
                declaration.contains("destinations: [.mac]") == false,
                let source = Self.firstCapture(#"sources:\s*\[\s*\"([^\"]+)"#, in: declaration)
            else { continue }
            discovered.append(TestBundle(
                name: name,
                sourceRoot: source.replacingOccurrences(of: "/**", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            ))
        }
        guard discovered.count >= 15 else {
            throw TestImpactError
                .invalidProject("Project.swift exposed only \(discovered.count) test bundles")
        }

        var discoveredSuites: [TestSuite] = []
        var freeBundles: Set<String> = []
        for bundle in discovered {
            let root = repo.appending(path: bundle.sourceRoot)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let files = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            ).flatMap { candidate -> [URL] in
                if candidate.pathExtension == "swift" { return [candidate] }
                guard candidate.hasDirectoryPath else { return [] }
                let enumerator = FileManager.default.enumerator(
                    at: candidate,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles],
                )
                return (enumerator?.allObjects as? [URL] ?? [])
                    .filter { $0.pathExtension == "swift" }
            }
            for file in files.sorted(by: { $0.path < $1.path }) {
                let relative = file.path.replacingOccurrences(of: repo.path + "/", with: "")
                let source = try String(contentsOf: file, encoding: .utf8)
                let parsed = Parser.parse(source: source)
                let visitor = TestSuiteVisitor(viewMode: .sourceAccurate)
                visitor.walk(parsed)
                discoveredSuites += visitor.suiteNames.map {
                    TestSuite(bundle: bundle.name, name: $0, sourcePath: relative)
                }
                if visitor.hasTopLevelTest {
                    freeBundles.insert(bundle.name)
                }
            }
        }
        bundles = discovered.sorted { $0.name < $1.name }
        suites = discoveredSuites.sorted { $0.identifier < $1.identifier }
        freeTestBundles = freeBundles
    }

    func bundle(containing path: String) -> TestBundle? {
        bundles.first { path == $0.sourceRoot || path.hasPrefix($0.sourceRoot + "/") }
    }

    func suites(in path: String) -> [TestSuite] {
        suites.filter { $0.sourcePath == path }
    }

    func allIdentifiers(for scheme: String) -> [String] {
        let bundleNames = Set(bundles.filter { $0.scheme == scheme }.map(\.name))
        let suiteIDs = suites.filter { bundleNames.contains($0.bundle) }.map(\.identifier)
        return (suiteIDs + freeTestBundles.filter(bundleNames.contains)).sorted()
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = expression.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }
}

final class TestSuiteVisitor: SyntaxVisitor {
    private(set) var hasTopLevelTest = false
    private var suitesWithTests: Set<String> = []
    private var typeStack: [String?] = []

    var suiteNames: [String] {
        suitesWithTests.sorted()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(name: node.name.text)
    }

    override func visitPost(_: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(name: node.name.text)
    }

    override func visitPost(_: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(name: node.name.text)
    }

    override func visitPost(_: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(name: node.name.text)
    }

    override func visitPost(_: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if node.attributeName.trimmedDescription == "Test" {
            if let suite = typeStack.reversed().compactMap(\.self).first {
                suitesWithTests.insert(suite)
            } else {
                hasTopLevelTest = true
            }
        }
        return .visitChildren
    }

    private func visitType(name: String) -> SyntaxVisitorContinueKind {
        typeStack.append(name.hasSuffix("Tests") ? name : nil)
        return .visitChildren
    }
}

struct IndexFile {
    let path: String
    let modificationDate: Date
    let declarations: Set<String>
    let references: Set<String>
}

struct SemanticIndex {
    let files: [String: IndexFile]
    let referencingFiles: [String: Set<String>]

    static func load(storePath: URL, libraryPath: URL, repo: URL) async throws -> SemanticIndex {
        guard FileManager.default.fileExists(atPath: storePath.path) else {
            throw TestImpactError.invalidIndex("index store does not exist: \(storePath.path)")
        }
        let library = try await IndexStoreLibrary.at(dylibPath: libraryPath)
        let store = try library.indexStore(at: storePath)
        var files: [String: IndexFile] = [:]
        // swiftformat:disable:next preferKeyPath
        let unitNames: [String] = store.unitNames(sorted: true).map { $0.string }
        for unitName in unitNames {
            let unit = try store.unit(named: unitName)
            guard unit.hasMainFile, unit.isSystemUnit == false else { continue }
            let absolute = URL(fileURLWithPath: unit.mainFile.string).standardizedFileURL.path
            guard absolute == repo.path || absolute.hasPrefix(repo.path + "/") else { continue }
            let relative = absolute.replacingOccurrences(of: repo.path + "/", with: "")
            var declarations: Set<String> = []
            var references: Set<String> = []
            let recordNames: [String] = unit.dependencies.compactMap {
                $0.kind == .record ? $0.name.string : nil
            }
            for recordName in recordNames {
                let record = try store.record(named: recordName)
                let occurrenceValues: [(
                    usr: String,
                    roles: IndexStoreSymbolRoles,
                    related: [String]
                )] =
                    record.occurrences.map { occurrence in
                        // swiftformat:disable:next preferKeyPath
                        let related = occurrence.relations.map { $0.symbol.usr.string }
                        return (occurrence.symbol.usr.string, occurrence.roles, related)
                    }
                for occurrence in occurrenceValues {
                    let usr = occurrence.usr
                    guard usr.isEmpty == false else { continue }
                    if occurrence.roles.contains(.declaration) || occurrence.roles
                        .contains(.definition)
                    {
                        declarations.insert(usr)
                    }
                    if occurrence.roles.contains(.reference) || occurrence.roles.contains(.call)
                        || occurrence.roles.contains(.read) || occurrence.roles.contains(.write)
                    {
                        references.insert(usr)
                    }
                    for related in occurrence.related {
                        if related.isEmpty == false { references.insert(related) }
                    }
                }
            }
            files[relative] = IndexFile(
                path: relative,
                modificationDate: unit.modificationDate,
                declarations: declarations,
                references: references,
            )
        }
        guard files.isEmpty == false else {
            throw TestImpactError.invalidIndex("index store contains no repository source records")
        }
        var reverse: [String: Set<String>] = [:]
        for file in files.values {
            for reference in file.references {
                reverse[reference, default: []].insert(file.path)
            }
        }
        return SemanticIndex(files: files, referencingFiles: reverse)
    }

    func reachableTestFiles(
        from changedFiles: [String],
        inventory: ProjectInventory,
    ) -> Set<String> {
        var pendingSymbols: [String] = []
        var visitedSymbols: Set<String> = []
        var visitedFiles = Set(changedFiles)
        var testFiles: Set<String> = []

        for path in changedFiles {
            if inventory.bundle(containing: path) != nil { testFiles.insert(path) }
            pendingSymbols += files[path]?.declarations ?? []
        }
        while let symbol = pendingSymbols.popLast() {
            guard visitedSymbols.insert(symbol).inserted else { continue }
            for path in referencingFiles[symbol] ?? [] where visitedFiles.insert(path).inserted {
                if inventory.bundle(containing: path) != nil {
                    testFiles.insert(path)
                } else {
                    pendingSymbols += files[path]?.declarations ?? []
                }
            }
        }
        return testFiles
    }
}

struct TestImpactEngine {
    let repo: URL
    let inventory: ProjectInventory
    let runner: CommandRunner

    init(repo: URL, runner: CommandRunner = CommandRunner()) throws {
        self.repo = repo.standardizedFileURL
        inventory = try ProjectInventory(repo: repo.standardizedFileURL)
        self.runner = runner
    }

    func select(
        changedFiles: [String],
        base: String,
        index: SemanticIndex?,
    ) throws -> TestImpactSelection {
        let normalized =
            Array(Set(changedFiles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
                .filter { $0.isEmpty == false }
                .sorted()
        let globalNames: Set = [
            "Package.swift",
            "Package.resolved",
            "Project.swift",
            "Tuist.swift",
            ".mise.toml",
            "test",
            "test-impact",
            "simulator",
            "ide",
        ]
        let global = normalized.contains { path in
            globalNames.contains(path) || path.hasPrefix(".github/") || path.hasPrefix(".circleci/")
        }
        let noChanges = normalized.isEmpty

        var identifiers: Set<String> = []
        var reasons: [SelectionReason] = []
        var fallback = global || noChanges
        if global || noChanges {
            for scheme in ["Stuff-iOS-Tests", "StuffSnapshotTests"] {
                identifiers.formUnion(inventory.allIdentifiers(for: scheme))
            }
            reasons.append(SelectionReason(
                path: "*",
                reason: noChanges ? "no-diff full-suite fallback" : "global invalidator",
                identifiers: identifiers.sorted(),
            ))
        } else {
            let swiftProduction = normalized
                .filter { $0.hasSuffix(".swift") && inventory.bundle(containing: $0) == nil }
            let directlyChangedTests = normalized.filter {
                $0.hasSuffix(".swift") && inventory.bundle(containing: $0) != nil
            }
            for path in directlyChangedTests {
                let suites = inventory.suites(in: path).map(\.identifier)
                if suites.isEmpty, let bundle = inventory.bundle(containing: path) {
                    identifiers.insert(bundle.name)
                    reasons.append(SelectionReason(
                        path: path,
                        reason: "test support or free test changed",
                        identifiers: [bundle.name],
                    ))
                } else {
                    identifiers.formUnion(suites)
                    reasons.append(SelectionReason(
                        path: path,
                        reason: "test suite changed",
                        identifiers: suites.sorted(),
                    ))
                }
            }
            for path in normalized where path.contains("/__Snapshots__/") {
                let parts = path.split(separator: "/")
                guard let marker = parts.firstIndex(of: "__Snapshots__"),
                      marker + 1 < parts.count else { continue }
                let suiteName = String(parts[marker + 1])
                let matches = inventory.suites.filter { $0.name == suiteName }.map(\.identifier)
                identifiers.formUnion(matches)
                reasons.append(SelectionReason(
                    path: path,
                    reason: "snapshot reference changed",
                    identifiers: matches.sorted(),
                ))
            }
            if swiftProduction.isEmpty == false {
                if let index {
                    var reached: Set<String> = []
                    var unresolved: [String] = []
                    for path in swiftProduction {
                        let pathReach = index.reachableTestFiles(
                            from: [path],
                            inventory: inventory,
                        )
                        if pathReach.isEmpty {
                            unresolved.append(path)
                        } else {
                            reached.formUnion(pathReach)
                        }
                    }
                    for path in reached.sorted() {
                        let suites = inventory.suites(in: path).map(\.identifier)
                        if suites.isEmpty, let bundle = inventory.bundle(containing: path) {
                            identifiers.insert(bundle.name)
                        } else {
                            identifiers.formUnion(suites)
                        }
                    }
                    reasons.append(SelectionReason(
                        path: swiftProduction.joined(separator: ","),
                        reason: "compiler-index reverse dependency",
                        identifiers: identifiers.sorted(),
                    ))
                    if unresolved.isEmpty == false {
                        reasons.append(SelectionReason(
                            path: unresolved.joined(separator: ","),
                            reason: "compiler index found no test dependency",
                            identifiers: [],
                        ))
                        fallback = true
                    }
                } else {
                    fallback = true
                }
            }
            let otherProduction = normalized.filter {
                inventory.bundle(containing: $0) == nil && $0.hasSuffix(".swift") == false
                    && $0.contains("/__Snapshots__/") == false
            }
            if otherProduction.isEmpty == false { fallback = true }

            if fallback {
                for scheme in ["Stuff-iOS-Tests", "StuffSnapshotTests"] {
                    identifiers.formUnion(inventory.allIdentifiers(for: scheme))
                }
                reasons.append(SelectionReason(
                    path: normalized.joined(separator: ","),
                    reason: "conservative full-suite fallback",
                    identifiers: identifiers.sorted(),
                ))
            }
        }

        var schemes: [String: SchemeSelection] = [:]
        for scheme in ["Stuff-iOS-Tests", "StuffSnapshotTests"] {
            let allowed = Set(inventory.allIdentifiers(for: scheme))
            let selected = identifiers.filter { identifier in
                allowed.contains(identifier) || allowed.contains { $0.hasPrefix(identifier + "/") }
            }.sorted()
            let scope = selected.isEmpty ? "none" : (Set(selected) == allowed ? "all" : "suites")
            schemes[scheme] = SchemeSelection(scope: scope, identifiers: selected)
        }
        let head = (try? runner.output(
            ["git", "rev-parse", "HEAD"],
            directory: repo,
        )) ?? "working-tree"
        var fingerprintHasher = SHA256()
        for path in normalized {
            let url = repo.appending(path: path)
            let data = (try? Data(contentsOf: url)) ?? Data()
            fingerprintHasher.update(data: Data(path.utf8))
            fingerprintHasher.update(data: Data([0]))
            fingerprintHasher.update(data: data)
            fingerprintHasher.update(data: Data([0]))
        }
        let fingerprint = fingerprintHasher.finalize().map { String(format: "%02x", $0) }.joined()
        return TestImpactSelection(
            formatVersion: Self.selectionFormatVersion,
            base: base,
            head: head,
            fingerprint: fingerprint,
            fallback: fallback,
            schemes: schemes,
            reasons: reasons,
        )
    }

    private static let selectionFormatVersion = 1
}
