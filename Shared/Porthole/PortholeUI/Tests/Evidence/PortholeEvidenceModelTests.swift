import Foundation
import PortholeRuntime
@testable import PortholeUI
import Testing

@MainActor
struct PortholeEvidenceModelTests {
    @Test func completedEvidenceSurvivesRehostingButExplicitRetryChecksTheOriginalScope(
    ) async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "preview"))
        await registry.setEnabled(true)
        let reference = try await registry.retain(EvidenceTestActor(), in: scope)
        let model = PortholeEvidenceModel(reference: .object(reference), registry: registry)
        await model.loadIfNeeded()
        guard case .loaded = model.state
        else { Issue.record("Initial evidence load failed"); return }
        await registry.setEnabled(false)
        await model.loadIfNeeded()
        guard case .loaded = model.state
        else { Issue.record("Rehosting discarded completed evidence"); return }
        await model.load()
        guard case let .failed(message) = model.state
        else { Issue.record("Explicit retry did not check the disabled scope"); return }
        await registry.setEnabled(true)
        await model.loadIfNeeded()
        guard case let .failed(retained) = model.state
        else { Issue.record("Rehosting silently retried a failure"); return }
        #expect(retained == message)
        await model.load()
        guard case .loaded = model.state
        else { Issue.record("Explicit retry failed to reload"); return }
        await registry.invalidate(scope)
        await model.load()
        guard case .failed = model.state
        else { Issue.record("Expired evidence was accepted"); return }
    }

    @Test func inspectsHandleMetadataWithoutCallingActorAndRejectsExpiredGeneration() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        let object = EvidenceTestActor()
        let reference = try await registry.retain(object, in: scope)
        let capability = PortholeCapability(
            id: .init(rawValue: "actor.read"),
            module: .init(rawValue: "PortholeUITests"),
            name: "EvidenceTestActor.read",
            summary: "Actor-owned read",
            parameters: [],
            result: .integer,
            effect: .read,
            source: nil,
            ownership: .actorInstance(typeName: "EvidenceTestActor"),
            availability: .callable,
        )
        try await registry.register(capability, in: scope) { _, _ in await .integer(object.read()) }
        let model = PortholeEvidenceModel(reference: .object(reference), registry: registry)
        await model.load()
        guard case let .loaded(.object(loaded)) = model.state
        else { Issue.record("Expected object metadata"); return }
        #expect(loaded.capabilities == [capability])
        #expect(await object.readCount == 0)
        _ = await registry.createScope(id: scope.id)
        await model.load()
        guard case .failed = model.state
        else { Issue.record("Expired handle was accepted"); return }
        #expect(await object.readCount == 0)
    }

    @Test func sourceLinksRequireExactHashAndScopeButSavedContentWorksOffline() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        let file = PortholeSourceFile(path: "Detector.swift", content: "one\ntwo")
        try await registry.installSourceArchive(
            String(decoding: JSONEncoder().encode([file]), as: UTF8.self),
            in: scope,
        )
        let source = PortholeEvidenceReference.Source(
            scope: scope,
            path: file.path,
            line: 2,
            sha256: file.sha256,
        )
        let model = PortholeEvidenceModel(reference: .source(source), registry: registry)
        await model.load()
        guard case let .loaded(.source(loaded)) = model.state
        else { Issue.record("Expected source"); return }
        #expect(loaded.line == 2)
        #expect(loaded.file == file)
        let mismatch = PortholeEvidenceModel(
            reference: .source(.init(
                scope: scope,
                path: file.path,
                line: 1,
                sha256: String(repeating: "0", count: 64),
            )),
            registry: registry,
        )
        await mismatch.load()
        guard case .failed = mismatch.state
        else { Issue.record("Mismatched source was accepted"); return }
        await registry.invalidate(scope)
        await model.load()
        guard case .failed = model.state
        else { Issue.record("Expired source scope was accepted"); return }
        let saved = PortholeEvidenceModel(reference: .savedSource(file), registry: registry)
        await saved.load()
        guard case let .loaded(.source(offline)) = saved.state
        else { Issue.record("Saved source became unavailable"); return }
        #expect(offline.file == file)
    }

    @Test func frozenContextRemainsReadableWhenLiveRelatedContextExpires() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        let context = PortholeContext(
            id: .init(rawValue: "issue"),
            title: "Captured issue",
            scope: scope,
            capturedAt: Date(),
            values: .object(["flight": .bool(false)]),
            objects: [],
            links: [],
            source: nil,
        )
        try await registry.capture(context)
        let link = PortholeContextLink(id: context.id, label: "Issue", relation: "origin")
        let related = PortholeEvidenceModel(
            reference: .contextLink(link, scope: scope),
            registry: registry,
        )
        await related.load()
        guard case let .loaded(.context(loaded)) = related.state
        else { Issue.record("Expected related context"); return }
        #expect(loaded.capture == context)
        await registry.invalidate(scope)
        await related.load()
        guard case .failed = related.state
        else { Issue.record("Expired related context was accepted"); return }
        let saved = PortholeEvidenceModel(reference: .context(context), registry: registry)
        await saved.load()
        guard case let .loaded(.context(frozen)) = saved.state
        else { Issue.record("Frozen capture was lost"); return }
        #expect(frozen.capture == context)
    }
}
