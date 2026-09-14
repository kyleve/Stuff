import Foundation
import PortholeGitHub
import PortholeRuntime
@testable import PortholeUI
import Testing

@MainActor
struct PortholeGitHubConfigurationTests {
    @Test func repeatedConfigurationAndScopeReplacementShareOneWorkspaceAndRegisterOnce(
    ) async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        await registry.setEnabled(true)
        let firstScope = await registry.createScope(id: .init(rawValue: "test"))
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(firstScope))
        let storage = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .appending(path: "workspace.json")
        let keychain = UUID().uuidString
        func configure() async throws {
            try await controller.configureGitHub(
                storageURL: storage,
                keychainService: keychain,
                clientID: "",
                installedBuildIdentity: "fixture",
                isDirty: false,
                initialRepository: GitHubRepository(
                    owner: "fixture",
                    name: "Example",
                ),
                initialBranch: "main",
            )
        }
        async let first: Void = configure()
        async let second: Void = configure()
        try await first; try await second
        let original = try #require(controller.github)
        #expect(try await registry.capabilities(in: firstScope).count == 6)
        controller.dismiss()
        let secondScope = await registry.createScope(id: firstScope.id)
        controller.present(origin: .application(secondScope))
        try await configure()
        #expect(controller.github === original)
        #expect(try await registry.capabilities(in: secondScope).count == 6)
        #expect(controller.githubConfigurationError == nil)
    }

    @Test func nativeSetupAcceptsMissingPublicClientIDAndExportsNoPublicationCapability(
    ) async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(scope))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try await controller.configureGitHub(
            storageURL: directory.appending(path: "workspace.json"),
            keychainService: UUID().uuidString,
            clientID: "",
            installedBuildIdentity: "fixture",
            isDirty: false,
            initialRepository: GitHubRepository(owner: "fixture", name: "Example"),
            initialBranch: "main",
        )
        #expect(try #require(controller.github).needsClientID)
        let capabilities = try await registry.capabilities(in: scope)
        #expect(capabilities.count == 6)
        #expect(capabilities.allSatisfy { $0.effect == .read || $0.effect == .isolated })
        #expect(!capabilities
            .contains { $0.id.rawValue.contains("publish") || $0.id.rawValue.contains("approve") })
    }

    @Test func agentWorkspaceEditsRequireCurrentRevisionAndStopAtSavedReview() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        let store = try GitHubWorkspaceStore(storageURL: nil)
        try await PortholeGitHubWorkspaceCapabilities.install(
            store: store,
            client: PortholeGitHubUIRepository(),
            installedSource: PortholeGitHubUITestSupport.installed(),
            registry: registry,
            scope: scope,
        )
        let loaded = try await store.load(
            base: PortholeGitHubUITestSupport.base(),
            installedSource: PortholeGitHubUITestSupport.installed(),
        )
        let arguments = PortholeValue.object([
            "revision": .string(loaded.revision.uuidString),
            "path": .string("Sources/Example.swift"),
            "text": .string("let value = 2\n"),
            "mode": .string("100644"),
        ])
        _ = try await registry.invoke(.init(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.github.set_text"),
            receiver: nil,
            arguments: arguments,
        ))
        await #expect(throws: (any Error).self) {
            try await registry.invoke(.init(
                id: UUID(),
                scope: scope,
                capabilityID: .init(rawValue: "porthole.github.set_text"),
                receiver: nil,
                arguments: arguments,
            ))
        }
        let edited = try await store.snapshot()
        _ = try await registry.invoke(.init(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.github.prepare_review"),
            receiver: nil,
            arguments: .object([
                "revision": .string(edited.revision.uuidString),
                "title": .string("Fix value"),
                "body": .string("Correct result"),
                "evidence": .string("synthetic"),
            ]),
        ))
        guard case .prepared = try await store.snapshot().review
        else { Issue.record("Expected saved review only"); return }
    }
}
