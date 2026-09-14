import Foundation
import PortholeRuntime
@testable import PortholeUI
import Testing

@MainActor
struct PortholeRemoteEvidenceReaderTests {
    @Test func readsPagedSourceAndTypedHandlesThroughHostCapabilities() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let file = PortholeSourceFile(
            path: "Detector.swift",
            content: (0 ..< 450).map { "line \($0)" }.joined(separator: "\n") + "\n",
        )
        let boundaryFiles = [
            PortholeSourceFile(path: "Empty.swift", content: ""),
            PortholeSourceFile(path: "Blank.swift", content: "\n"),
            PortholeSourceFile(path: "Trailing.swift", content: "one\n"),
        ]
        try await registry.installSourceArchive(
            String(decoding: JSONEncoder().encode([file] + boundaryFiles), as: UTF8.self),
            in: scope,
        )
        let reference = try await registry.retain(EvidenceTestActor(), in: scope)
        var calls: [PortholeInvocation] = []
        let reader = PortholeRemoteEvidenceReader(
            catalog: { try await registry.capabilities(in: $0) },
            invoke: {
                calls.append($0)
                return try await registry.invoke($0)
            },
        )
        #expect(try await reader.source(path: file.path, in: scope) == file)
        #expect(calls.map { $0.arguments["offset"] } == [.integer(0), .integer(200), .integer(400)])
        #expect(Set(calls.map(\.id)).count == calls.count)
        for boundary in boundaryFiles {
            #expect(try await reader.source(path: boundary.path, in: scope) == boundary)
        }
        #expect(try await reader.objects(in: scope) == [reference])
        await registry.invalidate(scope)
        await #expect(throws: PortholeError.self) { try await reader.objects(in: scope) }
    }

    @Test func rejectsChangedPageIdentityAndCorruptContent() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let file = PortholeSourceFile(path: "Detector.swift", content: "one\ntwo")
        try await registry.installSourceArchive(
            String(decoding: JSONEncoder().encode([file]), as: UTF8.self),
            in: scope,
        )
        let corruptions: [PortholeValue] = try [
            .object(["scope": .encoding(PortholeScopeToken(id: scope.id, generation: UUID()))]),
            .object(["sha256": .string(String(repeating: "0", count: 64))]),
            .object(["firstLine": .integer(2)]),
            .object(["text": .string("different\ncontent")]),
            .object(["totalLines": .integer(100_001)]),
        ]
        for corruption in corruptions {
            let reader = PortholeRemoteEvidenceReader(
                catalog: { try await registry.capabilities(in: $0) },
                invoke: { invocation in
                    guard case var .object(fields) = try await registry.invoke(invocation),
                          case let .object(replacements) = corruption
                    else {
                        throw PortholeError.invalidArguments("Expected source page")
                    }
                    fields.merge(replacements) { _, replacement in replacement }
                    return .object(fields)
                },
            )
            await #expect(throws: PortholeError.self) { try await reader.source(
                path: file.path,
                in: scope,
            ) }
        }
    }

    @Test func missingRemoteProviderFailsBeforeAnyInvocation() async {
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        var invoked = false
        let reader = PortholeRemoteEvidenceReader(
            catalog: { _ in [] },
            invoke: { _ in invoked = true; return .null },
        )
        await #expect(throws: PortholeError.self) { try await reader.source(
            path: "file.swift",
            in: scope,
        ) }
        #expect(!invoked)
    }
}
