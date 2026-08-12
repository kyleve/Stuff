import Foundation

/// Owns rollback-safe mutations of Where's app-icon catalogs and manifest.
public struct IconsService: Sendable {
    private struct Layout {
        let appCatalog: URL
        let previewCatalog: URL
        let manifest: URL
    }

    private let fileSystem: any FileSystem
    private let terminal: any Terminal
    private let repository: URL
    private let transactionIdentifier: @Sendable () -> String

    public init(
        fileSystem: any FileSystem,
        terminal: any Terminal,
        repository: URL,
        transactionIdentifier: @escaping @Sendable () -> String,
    ) {
        self.fileSystem = fileSystem
        self.terminal = terminal
        self.repository = repository
        self.transactionIdentifier = transactionIdentifier
    }

    public func run(_ request: IconsRequest) async throws {
        let layout = Layout(
            appCatalog: repository.appending(
                path: "Where/Where/Resources/AppIcon.xcassets",
                directoryHint: .isDirectory,
            ),
            previewCatalog: repository.appending(
                path: "Where/WhereUI/Sources/Resources/AppIconPreviews.xcassets",
                directoryHint: .isDirectory,
            ),
            manifest: repository.appending(
                path: "Where/WhereUI/Sources/Resources/AppIcons.json",
            ),
        )
        try validateLayout(layout)
        let planner = IconCatalogPlanner()
        let manifest = try planner.decodeManifest(
            fileSystem.read(layout.manifest),
            pathDescription: relativePath(layout.manifest),
        )

        switch request {
            case .list:
                try await list(manifest)
            case let .add(request):
                try await add(request, manifest: manifest, layout: layout, planner: planner)
            case let .remove(request):
                try await remove(request, manifest: manifest, layout: layout, planner: planner)
        }
    }

    private func list(_ manifest: AppIconManifest) async throws {
        guard manifest.icons.isEmpty == false else {
            try await terminal.write("(no icons in the manifest)\n", to: .standardOutput)
            return
        }
        let idWidth = manifest.icons.map(\.id.count).max() ?? 0
        let nameWidth = manifest.icons.map(\.displayName.count).max() ?? 0
        for icon in manifest.icons {
            let alternate = icon.alternateIconName ?? "(primary)"
            try await terminal.write(
                "  \(padded(icon.id, to: idWidth))  " +
                    "\(padded(icon.displayName, to: nameWidth))  \(alternate)\n",
                to: .standardOutput,
            )
        }
    }

    private func add(
        _ request: IconAddRequest,
        manifest: AppIconManifest,
        layout: Layout,
        planner: IconCatalogPlanner,
    ) async throws {
        let lightURL = resolveUserPath(request.lightPath)
        let light = try image(at: lightURL, userPath: request.lightPath)
        let dark = try request.darkPath.map { path in
            try image(at: resolveUserPath(path), userPath: path)
        }
        let tinted = try request.tintedPath.map { path in
            try image(at: resolveUserPath(path), userPath: path)
        }
        let plan = try planner.addition(
            manifest: manifest,
            light: light,
            lightFilename: request.lightPath,
            name: request.name,
            id: request.id,
            dark: dark,
            tinted: tinted,
        )
        let appTarget = layout.appCatalog.appending(
            path: "\(plan.setName).appiconset",
            directoryHint: .isDirectory,
        )
        let previewTarget = layout.previewCatalog.appending(
            path: "\(plan.setName).imageset",
            directoryHint: .isDirectory,
        )
        for target in [appTarget, previewTarget] where fileSystem.kind(of: target) != .missing {
            throw IconCatalogFailure.message("\(relativePath(target)) already exists")
        }

        let renderer = IconCatalogRenderer()
        let manifestData = try renderer.manifestData(plan.manifest)
        let appContents = try renderer.appContentsData(
            setName: plan.setName,
            hasDark: plan.dark != nil,
            hasTinted: plan.tinted != nil,
        )
        let previewContents = try renderer.previewContentsData(
            setName: plan.setName,
            hasDark: plan.dark != nil,
        )
        try validateOutputs(
            manifestData: manifestData,
            expectedManifest: plan.manifest,
            contents: [appContents, previewContents],
            planner: planner,
            manifestPath: relativePath(layout.manifest),
        )
        if request.dryRun {
            try await terminal.write(
                "Would add \"\(plan.icon.displayName)\" (id: \(plan.icon.id), " +
                    "asset: \(plan.setName)); no files changed.\n",
                to: .standardOutput,
            )
            return
        }

        let transactionRoot = try makeTransactionRoot()
        var preserveTransactionRootForRecovery = false
        defer {
            if preserveTransactionRootForRecovery == false {
                try? fileSystem.removeItem(at: transactionRoot)
            }
        }
        let stage = transactionRoot.appending(path: "stage", directoryHint: .isDirectory)
        let stagedApp = stage.appending(path: "app", directoryHint: .isDirectory)
        let stagedPreview = stage.appending(path: "preview", directoryHint: .isDirectory)
        let stagedManifest = stage.appending(path: "AppIcons.json")
        try fileSystem.createDirectory(at: stagedApp, withIntermediateDirectories: true)
        try fileSystem.createDirectory(at: stagedPreview, withIntermediateDirectories: true)
        try writeImages(plan, to: stagedApp, preview: stagedPreview)
        try fileSystem.write(
            appContents,
            to: stagedApp.appending(path: "Contents.json"),
            atomically: false,
        )
        try fileSystem.write(
            previewContents,
            to: stagedPreview.appending(path: "Contents.json"),
            atomically: false,
        )
        try fileSystem.write(manifestData, to: stagedManifest, atomically: false)

        do {
            try FileReplacementTransaction(fileSystem: fileSystem).commit(
                [
                    FileReplacement(target: appTarget, staged: stagedApp),
                    FileReplacement(target: previewTarget, staged: stagedPreview),
                    FileReplacement(target: layout.manifest, staged: stagedManifest),
                ],
                backupDirectory: transactionRoot.appending(path: "backup"),
            )
        } catch let failure as FileReplacementTransactionFailure {
            preserveTransactionRootForRecovery = true
            throw failure
        }
        try await terminal.write(
            "Added \"\(plan.icon.displayName)\" (id: \(plan.icon.id), asset: \(plan.setName)).\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "Run `./ide --no-open` to regenerate so the new icon is compiled in.\n",
            to: .standardOutput,
        )
    }

    private func remove(
        _ request: IconRemoveRequest,
        manifest: AppIconManifest,
        layout: Layout,
        planner: IconCatalogPlanner,
    ) async throws {
        let plan = try planner.removal(manifest: manifest, target: request.target)
        guard let setName = plan.icon.alternateIconName else {
            throw IconCatalogFailure.message("the primary \"Classic\" icon can't be removed")
        }
        let renderer = IconCatalogRenderer()
        let manifestData = try renderer.manifestData(plan.manifest)
        try validateOutputs(
            manifestData: manifestData,
            expectedManifest: plan.manifest,
            contents: [],
            planner: planner,
            manifestPath: relativePath(layout.manifest),
        )
        if request.dryRun {
            try await terminal.write(
                "Would remove \"\(plan.icon.displayName)\" (id: \(plan.icon.id)); " +
                    "no files changed.\n",
                to: .standardOutput,
            )
            return
        }

        let transactionRoot = try makeTransactionRoot()
        var preserveTransactionRootForRecovery = false
        defer {
            if preserveTransactionRootForRecovery == false {
                try? fileSystem.removeItem(at: transactionRoot)
            }
        }
        let stage = transactionRoot.appending(path: "stage", directoryHint: .isDirectory)
        let stagedManifest = stage.appending(path: "AppIcons.json")
        try fileSystem.createDirectory(at: stage, withIntermediateDirectories: true)
        try fileSystem.write(manifestData, to: stagedManifest, atomically: false)
        do {
            try FileReplacementTransaction(fileSystem: fileSystem).commit(
                [
                    FileReplacement(
                        target: layout.appCatalog.appending(
                            path: "\(setName).appiconset",
                            directoryHint: .isDirectory,
                        ),
                        staged: nil,
                    ),
                    FileReplacement(
                        target: layout.previewCatalog.appending(
                            path: "\(setName).imageset",
                            directoryHint: .isDirectory,
                        ),
                        staged: nil,
                    ),
                    FileReplacement(target: layout.manifest, staged: stagedManifest),
                ],
                backupDirectory: transactionRoot.appending(path: "backup"),
            )
        } catch let failure as FileReplacementTransactionFailure {
            preserveTransactionRootForRecovery = true
            throw failure
        }
        try await terminal.write(
            "Removed \"\(plan.icon.displayName)\" (id: \(plan.icon.id)).\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "If it was the active icon, the app falls back to Classic on next launch.\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "Run `./ide --no-open` to regenerate.\n",
            to: .standardOutput,
        )
    }

    private func writeImages(
        _ plan: IconAdditionPlan,
        to appDirectory: URL,
        preview previewDirectory: URL,
    ) throws {
        let lightName = "\(plan.setName).png"
        try fileSystem.write(
            plan.light.data,
            to: appDirectory.appending(path: lightName),
            atomically: false,
        )
        try fileSystem.write(
            plan.light.data,
            to: previewDirectory.appending(path: lightName),
            atomically: false,
        )
        if let dark = plan.dark {
            let name = "\(plan.setName)-Dark.png"
            try fileSystem.write(
                dark.data,
                to: appDirectory.appending(path: name),
                atomically: false,
            )
            try fileSystem.write(
                dark.data,
                to: previewDirectory.appending(path: name),
                atomically: false,
            )
        }
        if let tinted = plan.tinted {
            try fileSystem.write(
                tinted.data,
                to: appDirectory.appending(path: "\(plan.setName)-Tinted.png"),
                atomically: false,
            )
        }
    }

    private func validateLayout(_ layout: Layout) throws {
        let invalid = [layout.manifest, layout.appCatalog, layout.previewCatalog].filter {
            fileSystem.kind(of: $0) == .missing
        }
        guard invalid.isEmpty else {
            throw IconCatalogFailure.message(
                "couldn't find \(invalid.map(relativePath).joined(separator: ", ")) — " +
                    "run ./icons from the repo root",
            )
        }
        guard fileSystem.kind(of: layout.manifest) == .file,
              fileSystem.kind(of: layout.appCatalog) == .directory,
              fileSystem.kind(of: layout.previewCatalog) == .directory
        else {
            throw IconCatalogFailure
                .message("the app-icon repository layout has invalid item types")
        }
    }

    private func validateOutputs(
        manifestData: Data,
        expectedManifest: AppIconManifest,
        contents: [Data],
        planner: IconCatalogPlanner,
        manifestPath: String,
    ) throws {
        let decoded = try planner.decodeManifest(manifestData, pathDescription: manifestPath)
        guard decoded == expectedManifest else {
            throw IconCatalogFailure.message("generated icon manifest failed round-trip validation")
        }
        for data in contents {
            guard try (JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                throw IconCatalogFailure.message("generated asset Contents.json is invalid")
            }
        }
    }

    private func image(at url: URL, userPath: String) throws -> IconImageData {
        guard fileSystem.kind(of: url) == .file else {
            throw IconCatalogFailure.message("no such file: \(userPath)")
        }
        return try IconImageData(data: fileSystem.read(url), pathDescription: userPath)
    }

    private func makeTransactionRoot() throws -> URL {
        let root = repository.appending(
            path: ".stuff-icons-transaction-\(transactionIdentifier())",
            directoryHint: .isDirectory,
        )
        guard fileSystem.kind(of: root) == .missing else {
            throw IconCatalogFailure
                .message("transaction staging path already exists: \(root.path)")
        }
        try fileSystem.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func resolveUserPath(_ path: String) -> URL {
        path.hasPrefix("/")
            ? URL(filePath: path)
            : URL(filePath: path, relativeTo: repository).standardizedFileURL
    }

    private func relativePath(_ url: URL) -> String {
        let prefix = repository.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
            ? String(url.standardizedFileURL.path.dropFirst(prefix.count))
            : url.path
    }

    private func padded(_ value: String, to width: Int) -> String {
        value + String(repeating: " ", count: max(0, width - value.count))
    }
}
