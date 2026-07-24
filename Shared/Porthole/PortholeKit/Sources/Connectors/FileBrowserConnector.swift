import Foundation
import PortholeCore

/// The built-in `files` connector: browse the app's sandbox roots (and any
/// configured App Group containers) and read small files. Read-only in v1, with
/// a mandatory path-traversal guard. Auto-registered by ``Porthole``.
public final class FileBrowserConnector: PortholeConnector {
    /// A named, browsable root directory.
    struct Root {
        let name: String
        let url: URL
    }

    public let descriptor = PortholeConnectorDescriptor(
        id: "files",
        title: "Files",
        summary: "Browse the app's sandbox directories and App Group containers, and read small files.",
        version: 1,
    )

    private let roots: [Root]

    /// The standard sandbox roots plus one per App Group container id.
    public convenience init(appGroupIdentifiers: [String]) {
        self.init(roots: Self.standardRoots(appGroupIdentifiers: appGroupIdentifiers))
    }

    /// Testing seam: browse an explicit set of roots.
    @_spi(Testing)
    public convenience init(roots: [String: URL]) {
        self.init(roots: roots.sorted { $0.key < $1.key }.map { Root(name: $0.key, url: $0.value) })
    }

    private init(roots: [Root]) {
        self.roots = roots
    }

    private static func standardRoots(appGroupIdentifiers: [String]) -> [Root] {
        let manager = FileManager.default
        var roots: [Root] = []
        func add(_ name: String, _ directory: FileManager.SearchPathDirectory) {
            if let url = manager.urls(for: directory, in: .userDomainMask).first {
                roots.append(Root(name: name, url: url))
            }
        }
        add("documents", .documentDirectory)
        add("library", .libraryDirectory)
        add("application-support", .applicationSupportDirectory)
        add("caches", .cachesDirectory)
        roots.append(Root(name: "tmp", url: URL(fileURLWithPath: NSTemporaryDirectory())))
        for group in appGroupIdentifiers {
            if let url = manager.containerURL(forSecurityApplicationGroupIdentifier: group) {
                roots.append(Root(name: group, url: url))
            }
        }
        return roots
    }

    public func actions() -> [PortholeAction] {
        let roots = roots
        return [
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "read-file",
                    title: "Read file",
                    summary: "Read up to maxBytes of a file under a root, returned as data.",
                    parameters: .object([
                        "root": .string("Root name", allowedValues: roots.map(\.name)),
                        "path": .string("Path relative to the root"),
                        "maxBytes": .integer("Maximum bytes to read (default 262144)"),
                    ], required: ["root", "path"]),
                    isDestructive: false,
                ),
                handler: { parameters in
                    try Self.readFile(parameters, roots: roots)
                },
            ),
        ]
    }

    public func dataSources() -> [PortholeDataSource] {
        let roots = roots
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "roots",
                    title: "Roots",
                    summary: "The browsable root directories.",
                    rowSchema: .object([
                        "name": .string(),
                        "path": .string(),
                        "exists": .boolean(),
                    ]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in
                    let manager = FileManager.default
                    let rows = roots.map { root in
                        PortholeValue.object([
                            "name": .string(root.name),
                            "path": .string(root.url.path),
                            "exists": .bool(manager.fileExists(atPath: root.url.path)),
                        ])
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "entries",
                    title: "Entries",
                    summary: "The directory entries at a path under a root.",
                    rowSchema: .object([
                        "name": .string(),
                        "isDirectory": .boolean(),
                        "size": .integer(),
                        "modifiedAt": .date(),
                    ]),
                    filters: .object([
                        "root": .string("Root name", allowedValues: roots.map(\.name)),
                        "path": .string("Path relative to the root (default the root)"),
                    ], required: ["root"]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    try Self.entries(query.filters, roots: roots)
                },
            ),
        ]
    }

    // MARK: - Implementation

    private static func resolve(
        root name: String,
        path: String,
        roots: [Root],
    ) throws -> (root: Root, url: URL) {
        guard let root = roots.first(where: { $0.name == name }) else {
            throw PortholeError.invalidParameters("Unknown root `\(name)`")
        }
        let base = root.url.standardizedFileURL.resolvingSymlinksInPath()
        let target = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        // Traversal guard: the resolved target must stay within the root.
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard target.path == base.path || target.path.hasPrefix(basePath) else {
            throw PortholeError.invalidParameters("Path escapes the root")
        }
        return (root, target)
    }

    private static func entries(_ filters: PortholeValue, roots: [Root]) throws -> PortholePage {
        let name = filters["root"]?.stringValue ?? ""
        let path = filters["path"]?.stringValue ?? ""
        let (_, url) = try resolve(root: name, path: path, roots: roots)

        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw PortholeError.handlerFailed("Not a directory: \(path)")
        }
        let contents = try manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ],
        )
        let rows = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { entry -> PortholeValue in
                let values = try? entry.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ])
                var object: [String: PortholeValue] = [
                    "name": .string(entry.lastPathComponent),
                    "isDirectory": .bool(values?.isDirectory ?? false),
                ]
                if let size = values?.fileSize { object["size"] = .int(Int64(size)) }
                if let modified = values?
                    .contentModificationDate { object["modifiedAt"] = .date(modified) }
                return .object(object)
            }
        return PortholePage(rows: rows, totalCount: rows.count)
    }

    private static func readFile(
        _ parameters: PortholeValue,
        roots: [Root],
    ) throws -> PortholeValue {
        let name = parameters["root"]?.stringValue ?? ""
        let path = parameters["path"]?.stringValue ?? ""
        let maxBytes = Int(parameters["maxBytes"]?.intValue ?? 262_144)
        let (_, url) = try resolve(root: name, path: path, roots: roots)

        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw PortholeError.handlerFailed("Not a readable file: \(path)")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: max(0, maxBytes)) ?? Data()
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        let totalSize = (attributes?[.size] as? Int) ?? data.count
        return .object([
            "data": .data(data),
            "truncated": .bool(data.count < totalSize),
            "totalSize": .int(Int64(totalSize)),
        ])
    }
}
