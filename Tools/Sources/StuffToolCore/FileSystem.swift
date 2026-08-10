import Foundation

public enum FileItemKind: Equatable, Sendable {
    case missing
    case file
    case directory
}

public protocol FileSystem: Sendable {
    func kind(of url: URL) -> FileItemKind
    func contents(of directory: URL) throws -> [URL]
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL, atomically: Bool) throws
}

public struct FoundationFileSystem: FileSystem {
    public init() {}

    public func kind(of url: URL) -> FileItemKind {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    public func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
        )
    }

    public func createDirectory(
        at url: URL,
        withIntermediateDirectories: Bool,
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories,
        )
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL, atomically: Bool) throws {
        try data.write(to: url, options: atomically ? .atomic : [])
    }
}
