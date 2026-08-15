import Foundation

@main
enum TestImpactMain {
    private static let usage = """
    Usage:
      test-impact select [--base REF] [--index-store DIR] [--changed-files FILE] --output DIR
      test-impact explain --selection FILE

    `select` writes selection.json and one Xcode response file per test scheme.
    If semantic index data is unavailable or incomplete, selection safely expands.
    """

    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            print(usage)
            return
        }
        arguments.removeFirst()
        switch command {
            case "--help", "-h", "help":
                print(usage)
            case "select":
                try await select(arguments)
            case "explain":
                try explain(arguments)
            default:
                throw TestImpactError.invalidArguments("unknown command: \(command)")
        }
    }

    private static func select(_ arguments: [String]) async throws {
        var base = "origin/main"
        var indexStore: URL?
        var changedFiles: URL?
        var output: URL?
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
                case "--base": base = try requireValue(iterator.next(), after: argument)
                case "--index-store": indexStore = try URL(fileURLWithPath: requireValue(
                        iterator.next(),
                        after: argument,
                    ))
                case "--changed-files": changedFiles = try URL(fileURLWithPath: requireValue(
                        iterator.next(),
                        after: argument,
                    ))
                case "--output": output = try URL(fileURLWithPath: requireValue(
                        iterator.next(),
                        after: argument,
                    ))
                default: throw TestImpactError
                .invalidArguments("unknown select argument: \(argument)")
            }
        }
        guard let output else { throw TestImpactError.invalidArguments("select requires --output") }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runner = CommandRunner()
        let changed: [String]
        if let changedFiles {
            changed = try String(contentsOf: changedFiles, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init)
        } else {
            let mergeBase = try runner.output(["git", "merge-base", "HEAD", base], directory: repo)
            let committed = try runner.output(
                ["git", "diff", "--name-only", mergeBase],
                directory: repo,
            )
            let untracked = try runner.output(
                ["git", "ls-files", "--others", "--exclude-standard"],
                directory: repo,
            )
            changed = (committed + "\n" + untracked).split(whereSeparator: \.isNewline)
                .map(String.init)
            base = mergeBase
        }
        let engine = try TestImpactEngine(repo: repo, runner: runner)
        let semanticIndex: SemanticIndex?
        if let indexStore {
            let developer = try runner.output(["xcode-select", "-p"], directory: repo)
            let library = URL(fileURLWithPath: developer)
                .appending(path: "Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib")
            semanticIndex = try await SemanticIndex.load(
                storePath: indexStore,
                libraryPath: library,
                repo: repo,
            )
        } else {
            semanticIndex = nil
        }
        let selection = try engine.select(changedFiles: changed, base: base, index: semanticIndex)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(selection) + Data("\n".utf8))
            .write(to: output.appending(path: "selection.json"))
        for (scheme, value) in selection.schemes {
            let contents = value.identifiers.map { $0 + "\n" }.joined()
            try Data(contents.utf8).write(to: output.appending(path: scheme + ".txt"))
        }
        print("Selected tests: " + selection.schemes.sorted(by: { $0.key < $1.key }).map {
            "\($0.key)=\($0.value.identifiers.count)"
        }.joined(separator: ", ") + (selection.fallback ? " (fallback)" : ""))
    }

    private static func explain(_ arguments: [String]) throws {
        guard arguments.count == 2, arguments[0] == "--selection" else {
            throw TestImpactError.invalidArguments("explain requires --selection PATH")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let selection = try JSONDecoder().decode(TestImpactSelection.self, from: data)
        print("Base: \(selection.base)")
        print("Head: \(selection.head)")
        print("Fallback: \(selection.fallback ? "yes" : "no")")
        for reason in selection.reasons {
            print("\(reason.path): \(reason.reason)")
            reason.identifiers.forEach { print("  \($0)") }
        }
    }

    private static func requireValue(_ value: String?, after argument: String) throws -> String {
        guard let value
        else { throw TestImpactError.invalidArguments("\(argument) requires a value") }
        return value
    }
}
