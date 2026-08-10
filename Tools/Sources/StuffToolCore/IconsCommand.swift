import ArgumentParser
import Foundation

public struct IconAddRequest: Equatable, Sendable {
    public let lightPath: String
    public let name: String?
    public let id: String?
    public let darkPath: String?
    public let tintedPath: String?
    public let dryRun: Bool

    public init(
        lightPath: String,
        name: String? = nil,
        id: String? = nil,
        darkPath: String? = nil,
        tintedPath: String? = nil,
        dryRun: Bool = false,
    ) {
        self.lightPath = lightPath
        self.name = name
        self.id = id
        self.darkPath = darkPath
        self.tintedPath = tintedPath
        self.dryRun = dryRun
    }
}

public struct IconRemoveRequest: Equatable, Sendable {
    public let target: String
    public let dryRun: Bool

    public init(target: String, dryRun: Bool = false) {
        self.target = target
        self.dryRun = dryRun
    }
}

public enum IconsRequest: Equatable, Sendable {
    case add(IconAddRequest)
    case remove(IconRemoveRequest)
    case list
}

public struct IconsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "icons",
        abstract: "Add, remove, or list selectable Where app icons.",
        discussion: """
        Keeps the app catalog, picker preview catalog, and AppIcons.json in
        sync. Add and remove commit as a rollback-safe transaction.
        """,
    )

    @Option(name: .customLong("add"), help: "Add a 1024x1024 light PNG.")
    var addPath: String?

    @Option(name: .customLong("remove"), help: "Remove an icon by name or id.")
    var removeTarget: String?

    @Flag(help: "List the current icon manifest.")
    var list = false

    @Option(help: "Display name for an added icon.")
    var name: String?

    @Option(help: "Stable manifest id for an added icon.")
    var id: String?

    @Option(help: "Dark-appearance 1024x1024 PNG.")
    var dark: String?

    @Option(help: "Tinted-appearance 1024x1024 PNG.")
    var tinted: String?

    @Flag(help: "Validate and describe a mutation without changing files.")
    var dryRun = false

    public init() {}

    public func makeRequest() throws -> IconsRequest {
        let modeCount = [addPath != nil, removeTarget != nil, list].count(where: { $0 })
        guard modeCount == 1 else {
            throw IconCatalogFailure.message("choose --add, --remove, or --list")
        }
        if let addPath {
            try requireValue(addPath, option: "--add")
            try requireOptionalValue(name, option: "--name")
            try requireOptionalValue(id, option: "--id")
            try requireOptionalValue(dark, option: "--dark")
            try requireOptionalValue(tinted, option: "--tinted")
            return .add(
                IconAddRequest(
                    lightPath: addPath,
                    name: name,
                    id: id,
                    darkPath: dark,
                    tintedPath: tinted,
                    dryRun: dryRun,
                ),
            )
        }

        guard name == nil, id == nil, dark == nil, tinted == nil else {
            throw IconCatalogFailure.message(
                "--name, --id, --dark, and --tinted require --add",
            )
        }
        if let removeTarget {
            try requireValue(removeTarget, option: "--remove")
            return .remove(IconRemoveRequest(target: removeTarget, dryRun: dryRun))
        }
        guard dryRun == false else {
            throw IconCatalogFailure.message("--dry-run requires --add or --remove")
        }
        return .list
    }

    public mutating func run() async throws {
        let terminal = StandardTerminal()
        let environment = ProcessInfo.processInfo.environment
        let repository = environment["STUFF_REPOSITORY_ROOT"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory,
            )
        let service = IconsService(
            fileSystem: FoundationFileSystem(),
            terminal: terminal,
            repository: repository,
            transactionIdentifier: { UUID().uuidString },
        )
        do {
            try await service.run(makeRequest())
        } catch let failure as IconCatalogFailure {
            try await terminal.write("error: \(failure)\n", to: .standardError)
            throw ExitCode.failure
        } catch let failure as FileReplacementTransactionFailure {
            try await terminal.write("error: \(failure)\n", to: .standardError)
            throw ExitCode.failure
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            try await terminal.write("error: \(error)\n", to: .standardError)
            throw ExitCode.failure
        }
    }

    private func requireOptionalValue(_ value: String?, option: String) throws {
        if let value { try requireValue(value, option: option) }
    }

    private func requireValue(_ value: String, option: String) throws {
        guard value.isEmpty == false else {
            throw IconCatalogFailure.message("\(option) requires a value")
        }
    }
}
