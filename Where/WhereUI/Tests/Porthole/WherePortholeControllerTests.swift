import Foundation
import PortholeRuntime
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WherePortholeControllerTests {
    @Test func agentSetupFailureDoesNotDisableManualReopening() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        let libraryURL = fixture.directory.appending(path: "investigation.investigations")
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let selectionURL = libraryURL.appending(path: "selection.json")
        let unreadableSelection = Data("incomplete investigation index".utf8)
        try unreadableSelection.write(to: selectionURL)
        await fixture.controller.reconcile(scope: nil)
        let token = try #require(fixture.token)

        for _ in 0 ..< 2 {
            fixture.controller.captureMenuOrigin()
            await fixture.controller.presentCurrentScreen()
            #expect(fixture.controller.presentation.isPresented)
            #expect(fixture.controller.presentation.agent == nil)
            #expect(fixture.controller.presentation.agentConfigurationError != nil)
            #expect(fixture.token == token)
            #expect(await fixture.registry.isEnabled())
            _ = try await fixture.controller.presentation.execute(.init(
                id: UUID(),
                scope: token,
                capabilityID: .init(rawValue: "porthole.discover"),
                receiver: nil,
                arguments: .object([
                    "query": .string("source"),
                    "offset": .integer(0),
                    "limit": .integer(1),
                ]),
            ))
            fixture.controller.presentation.dismiss()
        }
        #expect(try Data(contentsOf: selectionURL) == unreadableSelection)
        await fixture.controller.invalidateScope()
    }

    @Test func screenshotCapabilityReusesTheImageCapturedBeforeTheMenu() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        await fixture.controller.reconcile(scope: nil)
        let token = try #require(fixture.token)
        let original = try fixture.screenshots.result.get()
        fixture.controller.captureMenuOrigin()
        await fixture.controller.presentCurrentScreen()
        #expect(fixture.controller.presentation.isPresented)
        fixture.screenshots.result = .success(Data("debugger credentials".utf8))
        fixture.controller.captureMenuOrigin()
        let value = try await fixture.registry.invoke(.init(
            id: UUID(),
            scope: token,
            capabilityID: .init(rawValue: "where.screenshot"),
            receiver: nil,
            arguments: .object([:]),
        ))
        #expect(value["base64"] == .string(original.base64EncodedString()))
        #expect(fixture.screenshots.captures == 1)
        await fixture.controller.invalidateScope()
    }

    @Test func unavailableScreenshotNeverFallsBackWhilePortholeIsPresented() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        await fixture.controller.reconcile(scope: nil)
        let token = try #require(fixture.token)
        fixture.screenshots.result = .failure(.unsupported("No window"))
        fixture.controller.captureMenuOrigin()
        await fixture.controller.presentCurrentScreen()
        #expect(fixture.controller.presentation.isPresented)
        fixture.screenshots.result = .success(Data("debugger credentials".utf8))
        await #expect(throws: PortholeError.self) {
            try await fixture.registry.invoke(.init(
                id: UUID(),
                scope: token,
                capabilityID: .init(rawValue: "where.screenshot"),
                receiver: nil,
                arguments: .object([:]),
            ))
        }
        #expect(fixture.screenshots.captures == 1)
        await fixture.controller.invalidateScope()
    }

    @Test func remainsInactiveUntilExplicitActivation() async {
        let fixture = WherePortholeTestFixture(enabled: false)
        defer { fixture.removeFiles() }
        let installations = WherePortholeInstallerProbe()
        fixture.controller.addModuleInstaller { _, _ in await installations.installed() }
        var captures = 0
        fixture.controller.enter(fixture.screen(title: "Disabled screen", depth: 1) {
            captures += 1
            return .string("private screen value")
        })
        #expect(await !(fixture.registry.isEnabled()))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        await fixture.controller.reconcile(scope: nil)
        fixture.controller.captureMenuOrigin()
        await fixture.controller.presentCurrentScreen()
        #expect(await !(fixture.registry.isEnabled()))
        #expect(!fixture.controller.presentation.isPresented)
        #expect(fixture.controller.remoteHost == nil)
        #expect(fixture.controller.presentation.agent == nil)
        #expect(fixture.controller.presentation.github == nil)
        #expect(fixture.controller.presentation.host == nil)
        #expect(await installations.count == 0)
        #expect(captures == 0)
        #expect(fixture.screenshots.captures == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        fixture.controller.isEnabled = true
        #expect(fixture.preferences.isPortholeEnabled)
        await fixture.controller.reconcile(scope: nil)
        #expect(await fixture.registry.isEnabled())
        #expect(fixture.token != nil)
        #expect(await installations.count == 1)
        await fixture.controller.invalidateScope()
    }

    @Test(arguments: ["issue", "day"])
    func freezesScreenValuesBeforeDeveloperNavigation(kind: String) async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        await fixture.controller.reconcile(scope: nil)
        _ = try #require(fixture.token)
        var values = PortholeValue.object(["kind": .string(kind), "day": .string("2026-09-13")])
        let original = values
        let screen = fixture.screen(title: "Selected \(kind)", depth: 2) { values }
        fixture.controller.enter(screen)
        fixture.controller.captureMenuOrigin()
        values = .object(["kind": .string("changed")])
        fixture.controller.leave(screen.id)
        fixture.controller.enter(fixture.screen(title: "Settings", depth: 3) { .null })
        await fixture.controller.presentCurrentScreen()
        guard case let .screen(context) = fixture.controller.presentation.origin else {
            Issue.record("Expected the original screen"); return
        }
        #expect(context.title == "Selected \(kind)")
        #expect(context.values == original)
        #expect(context.source == screen.source)
        await fixture.controller.invalidateScope()
    }

    @Test(arguments: [true, false])
    func selectsTheDeepestScreenRegardlessOfAppearanceOrder(parentFirst: Bool) async {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        await fixture.controller.reconcile(scope: nil)
        let parent = fixture.screen(title: "Your Year", depth: 0) { .integer(2026) }
        let child = fixture.screen(title: "Border drift", depth: 2) { .string("issue") }
        for screen in parentFirst ? [parent, child] :
            [child, parent]
        {
            fixture.controller.enter(screen)
        }
        fixture.controller.captureMenuOrigin()
        await fixture.controller.presentCurrentScreen()
        guard case let .screen(context) = fixture.controller.presentation.origin else {
            Issue.record("Expected a screen origin"); return
        }
        #expect(context.title == "Border drift")
        await fixture.controller.invalidateScope()
    }

    @Test func anApplicationOriginDoesNotAdoptALaterScreen() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        await fixture.controller.reconcile(scope: nil)
        let token = try #require(fixture.token)
        fixture.controller.captureMenuOrigin()
        fixture.controller.enter(fixture.screen(title: "Later screen", depth: 10) { .null })
        await fixture.controller.presentCurrentScreen()
        guard case let .application(origin) = fixture.controller.presentation.origin else {
            Issue.record("The global launch adopted a later screen"); return
        }
        #expect(origin == token)
        await fixture.controller.invalidateScope()
    }

    @Test func ignoresRetiredScreensAndInvalidatesRetainedRoots() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        let scope = try fixture.makeScope()
        await fixture.controller.reconcile(scope: scope)
        let token = try #require(fixture.token)
        let root = WherePortholeTestRoot()
        fixture.controller.enter(fixture.screen(title: "Logged-out root", depth: 20) { .null })
        fixture.controller.enter(.init(
            id: UUID(),
            owningScope: ObjectIdentifier(scope),
            depth: 1,
            title: "Current issue",
            source: .init(
                path: "Issue.swift",
                line: 12,
            ),
            capture: { .string("current") },
            roots: [root],
        ))
        fixture.controller.captureMenuOrigin()
        await fixture.controller.presentCurrentScreen()
        guard case let .screen(context) = fixture.controller.presentation.origin else {
            Issue.record("Expected the matching application scope"); return
        }
        #expect(context.title == "Current issue")
        let reference = try #require(context.objects.first)
        let resolved = try await fixture.registry.resolve(
            reference,
            as: WherePortholeTestRoot.self,
            in: token,
        )
        #expect(resolved === root)
        await fixture.controller.invalidateScope()
        #expect(!fixture.controller.presentation.isPresented)
        await #expect(throws: PortholeError.staleScope) {
            try await fixture.registry.resolve(reference, as: WherePortholeTestRoot.self, in: token)
        }
    }

    @Test func disablingDuringInstallationCannotPublishALateReadyScope() async {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        let gate = WherePortholeInstallationGate()
        fixture.controller.addModuleInstaller { _, _ in await gate.arrive() }
        let activation = Task { await fixture.controller.reconcile(scope: nil) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while await !(gate.hasArrived), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let arrived = await gate.hasArrived
        #expect(arrived)
        fixture.controller.isEnabled = false
        await fixture.controller.reconcile(scope: nil)
        await gate.release()
        await activation.value
        #expect(await !(fixture.registry.isEnabled()))
        #expect(fixture.token == nil)
        #expect(fixture.controller.remoteHost == nil)
        guard case .disabled = fixture.controller.state else {
            Issue.record("A late installation replaced disabled state"); return
        }
    }
}
