import Foundation
import PortholeCore

/// Reconstructs remote source through bounded read pages without a second application store.
struct PortholeRemoteEvidenceReader: PortholeEvidenceReading {
    let catalog: @MainActor (PortholeScopeToken) async throws -> [PortholeCapability]
    let invoke: @MainActor (PortholeInvocation) async throws -> PortholeValue

    func capabilities(in scope: PortholeScopeToken) async throws -> [PortholeCapability] {
        try await catalog(scope)
    }

    func objects(in scope: PortholeScopeToken) async throws -> [PortholeObjectReference] {
        try await require("porthole.objects", in: scope)
        let objects = try await read("porthole.objects", arguments: .object([:]), in: scope)
            .decode([PortholeObjectReference].self)
        guard objects.allSatisfy({ $0.scope == scope }) else {
            throw PortholeError
                .invalidArguments("Remote object metadata changed its scope generation")
        }
        return objects
    }

    func contexts(in scope: PortholeScopeToken) async throws -> [PortholeContext] {
        try await require("porthole.contexts", in: scope)
        let contexts = try await read("porthole.contexts", arguments: .object([:]), in: scope)
            .decode([PortholeContext].self)
        guard contexts.allSatisfy({ $0.scope == scope }) else {
            throw PortholeError
                .invalidArguments("Remote context metadata changed its scope generation")
        }
        return contexts
    }

    func source(path: String, in scope: PortholeScopeToken) async throws -> PortholeSourceFile {
        try await require("porthole.source.read", in: scope)
        var lines: [String] = []
        var expected: Page?
        var bytes = 0
        repeat {
            try Task.checkCancellation()
            let value = try await read("porthole.source.read", arguments: .object([
                "path": .string(path),
                "offset": .integer(Int64(lines.count)),
                "limit": .integer(200),
            ]), in: scope)
            let page = try value.decode(Page.self)
            guard page.path == path, page.scope == scope, page.firstLine == lines.count + 1,
                  (1 ... 100_000).contains(page.totalLines),
                  expected == nil ||
                  (page.sha256 == expected?.sha256 && page.totalLines == expected?.totalLines)
            else {
                throw PortholeError
                    .invalidArguments(
                        "Remote source page changed its scope, hash, path, or line range",
                    )
            }
            let pageLines = page.text.components(separatedBy: "\n")
            guard pageLines.count == min(200, page.totalLines - lines.count) else {
                throw PortholeError.invalidArguments("Remote source page is incomplete")
            }
            bytes += page.text.utf8.count + (expected == nil ? 0 : 1)
            guard bytes <= 10 * 1024 * 1024 else {
                throw PortholeError
                    .invalidArguments("Remote source exceeds the 10 MB inspection limit")
            }
            lines.append(contentsOf: pageLines)
            expected = page
        } while lines.count < (expected?.totalLines ?? 0)
        let file = PortholeSourceFile(path: path, content: lines.joined(separator: "\n"))
        guard file.sha256 == expected?.sha256 else {
            throw PortholeError.invalidArguments("Remote source content failed its SHA-256 check")
        }
        return file
    }

    private struct Page: Decodable {
        let path: String
        let firstLine: Int
        let scope: PortholeScopeToken
        let sha256: String
        let totalLines: Int
        let text: String
    }

    private func require(_ name: String, in scope: PortholeScopeToken) async throws {
        guard try await capabilities(in: scope).contains(where: {
            $0.id.rawValue == name && $0.effect == .read && $0.availability == .callable
        })
        else {
            throw PortholeError
                .invalidArguments("This remote host does not provide the read capability \(name)")
        }
    }

    private func read(
        _ name: String,
        arguments: PortholeValue,
        in scope: PortholeScopeToken,
    ) async throws -> PortholeValue {
        try await invoke(PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: name),
            receiver: nil,
            arguments: arguments,
        ))
    }
}
