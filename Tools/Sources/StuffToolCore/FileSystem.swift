import Foundation

public enum FileItemKind: Equatable, Sendable {
    case missing
    case file
    case directory
    case symbolicLink
}

public protocol FileSystem: Sendable {
    func kind(of url: URL) -> FileItemKind
    func contents(of directory: URL) throws -> [URL]
    func copyItem(at source: URL, to destination: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL, atomically: Bool) throws
    func setPosixPermissions(_ permissions: Int, at url: URL) throws
}

public struct FoundationFileSystem: FileSystem {
    public init() {}

    public func kind(of url: URL) -> FileItemKind {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType
        else {
            return .missing
        }
        return switch type {
            case .typeDirectory: .directory
            case .typeSymbolicLink: .symbolicLink
            default: .file
        }
    }

    public func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
        )
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
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

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
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

    public func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path,
        )
    }
}
