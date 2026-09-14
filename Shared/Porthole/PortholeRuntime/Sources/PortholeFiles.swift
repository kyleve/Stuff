import CryptoKit
import Foundation
import PortholeCore

/// Explicit host roots confine file operations; links cannot escape a root or enter an excluded
/// subtree.
public struct PortholeFiles: Sendable {
    public struct Root: Sendable {
        public let name: PortholeIdentifier<FileRoot>
        public let url: URL
        public let excludedPaths: [URL]
        public init(name: PortholeIdentifier<FileRoot>, url: URL, excludedPaths: [URL]) {
            self.name = name
            self.url = url.resolvingSymlinksInPath().standardizedFileURL
            self.excludedPaths = excludedPaths
                .map { $0.resolvingSymlinksInPath().standardizedFileURL }
        }
    }

    public enum FileRoot: Sendable {}
    private let roots: [Root]
    private let maximumBytes: Int

    public init(roots: [Root], maximumBytes: Int) {
        precondition(maximumBytes > 0)
        self.roots = roots; self.maximumBytes = maximumBytes
    }

    public func install(in registry: PortholeRegistry, scope: PortholeScopeToken) async throws {
        let parameters: [PortholeParameter] = [
            .init(name: "root", summary: "Host root name", schema: .string, required: true),
            .init(
                name: "path",
                summary: "Relative path within the root",
                schema: .string,
                required: true,
            ),
        ]
        try await register(
            "porthole.files.roots",
            parameters: [],
            effect: .read,
            registry: registry,
            scope: scope,
        ) { _, _ in
            .array(roots.map { .string($0.name.rawValue) })
        }
        let listParameters = parameters + [
            .init(
                name: "offset",
                summary: "Zero-based offset in this name-sorted directory snapshot",
                schema: .integer,
                required: true,
            ),
            .init(
                name: "limit",
                summary: "Maximum entries to return, from 1 through 200",
                schema: .integer,
                required: true,
            ),
        ]
        try await register(
            "porthole.files.list",
            parameters: listParameters,
            effect: .read,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            guard case let .integer(offset) = invocation.arguments["offset"], offset >= 0,
                  case let .integer(limit) = invocation.arguments["limit"],
                  (1 ... 200).contains(limit)
            else {
                throw PortholeError
                    .invalidArguments(
                        "offset must be nonnegative and limit must be from 1 through 200",
                    )
            }
            let entries = try access(invocation).entries(maximumCount: 10000)
            let start = Int(min(offset, Int64(entries.count)))
            let end = min(start + Int(limit), entries.count)
            return .object([
                "entries": .array(entries[start ..< end].map { .object([
                    "name": .string($0.name),
                    "isDirectory": .bool($0.isDirectory),
                    "isSymbolicLink": .bool($0.isSymbolicLink),
                    "bytes": .integer($0.bytes),
                ]) }),
                "nextOffset": end < entries.count ? .integer(Int64(end)) : .null,
                "total": .integer(Int64(entries.count)),
            ])
        }
        try await register(
            "porthole.files.read",
            parameters: parameters,
            effect: .read,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            let data = try access(invocation).read()
            return .object([
                "sha256": .string(hash(data)),
                "base64": .string(data.base64EncodedString()),
                "text": String(data: data, encoding: .utf8).map(PortholeValue.string) ?? .null,
            ])
        }
        let writeParameters = parameters + [
            .init(
                name: "expectedSHA256",
                summary: "Hash read before editing; null only for a new file",
                schema: .optional(.string),
                required: true,
            ),
            .init(
                name: "text",
                summary: "Complete proposed UTF-8 file contents",
                schema: .string,
                required: true,
            ),
        ]
        try await register(
            "porthole.files.write",
            parameters: writeParameters,
            effect: .mutation,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            let target = try access(invocation)
            guard let text = invocation.arguments["text"]?.stringValue
            else { throw PortholeError.invalidArguments("Missing text") }
            let data = Data(text.utf8)
            guard data.count <= maximumBytes else { throw PortholeError.capacityExceeded }
            let expected: String?
            switch invocation.arguments["expectedSHA256"] {
                case let .string(value): expected = value
                case .null: expected = nil
                case .none,
                     .some: throw PortholeError
                .invalidArguments("expectedSHA256 must be a string or null")
            }
            try target.write(data, expected: expected, hash: hash)
            return .object(["sha256": .string(hash(data)), "bytes": .integer(Int64(data.count))])
        }
    }

    func resolve(_ invocation: PortholeInvocation) throws -> URL {
        let selection = try access(invocation)
        try selection.validate()
        return selection.root.appending(path: selection.components.joined(separator: "/"))
    }

    private func access(_ invocation: PortholeInvocation) throws -> PortholeFileAccess {
        guard let name = invocation.arguments["root"]?.stringValue,
              let root = roots.first(where: { $0.name.rawValue == name }),
              let path = invocation.arguments["path"]?.stringValue, !path.hasPrefix("/"),
              !path.contains("\0")
        else {
            throw PortholeError.invalidArguments("Unknown root or invalid relative path")
        }
        let base = root.url
        let components = path.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !components.contains("..")
        else { throw PortholeError.invalidArguments("Parent traversal is not permitted") }
        let target = base.appending(path: components.joined(separator: "/")).standardizedFileURL
        func within(_ candidate: URL, _ parent: URL) -> Bool {
            candidate.path == parent.path || candidate.path.hasPrefix(parent.path + "/")
        }
        guard within(target, base),
              !root.excludedPaths.contains(where: { within(target, $0) })
        else {
            throw PortholeError.invalidArguments("Path is outside the permitted file roots")
        }
        return PortholeFileAccess(root: base, components: components, maximumBytes: maximumBytes)
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(
            format: "%02x",
            $0,
        ) }.joined()
    }

    private func register(
        _ name: String,
        parameters: [PortholeParameter],
        effect: PortholeEffect,
        registry: PortholeRegistry,
        scope: PortholeScopeToken,
        handler: @escaping PortholeRegistry.Handler,
    ) async throws {
        try await registry.register(
            .init(
                id: .init(rawValue: name),
                module: .init(rawValue: "PortholeRuntime"),
                name: name,
                summary: "Confined file operation; maximum \(maximumBytes) bytes per file",
                parameters: parameters,
                result: .any,
                effect: effect,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            ),
            in: scope,
            handler: handler,
        )
    }
}
