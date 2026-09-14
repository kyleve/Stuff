#if canImport(UIKit)
    import PortholeRuntime
    @testable import PortholeUI
    import SwiftUI
    import TestHostSupport
    import Testing
    import UIKit

    @MainActor
    struct PortholePresentationAnchorTests {
        @Test(arguments: [true, false], [true, false])
        func presentsAboveApplicationModalAndDismissesOnlyTheDebugger(
            externalDismissal: Bool,
            coversRoot: Bool,
        ) async throws {
            let fixture = try await PortholePresentationAnchorFixture(coversRoot: coversRoot)
            do {
                fixture.presentApplicationModal()
                try await fixture.wait("application modal appearance") {
                    fixture.modal.presentingViewController != nil && fixture.modal
                        .hasAppeared && !fixture.modal.isBeingPresented
                }
                fixture.controller.present(origin: .screen(fixture.context))
                try await fixture.wait("debugger presentation") {
                    fixture.modal.presentedViewController is PortholePresentationAnchor
                        .HostingController
                }
                let debugger = try #require(fixture.modal.presentedViewController)
                try await fixture
                    .wait("debugger presentation completion") { !debugger.isBeingPresented }
                #expect(fixture.controller.origin == .screen(fixture.context))
                #expect(fixture.root.presentedViewController === fixture.modal)
                if externalDismissal {
                    debugger.dismiss(animated: false)
                } else {
                    fixture.controller.dismiss()
                }
                try await fixture.wait("debugger dismissal") {
                    fixture.modal.presentedViewController == nil && !fixture.controller.isPresented
                }
                #expect(fixture.root.presentedViewController === fixture.modal)
            } catch {
                await fixture.close()
                throw error
            }
            await fixture.close()
        }

        @Test func replacementSessionSurvivesThePreviousDismissalCompletion() async throws {
            let fixture = try await PortholePresentationAnchorFixture(coversRoot: true)
            do {
                fixture.presentApplicationModal()
                try await fixture.wait("application modal appearance") {
                    fixture.modal.presentingViewController != nil && fixture.modal
                        .hasAppeared && !fixture.modal.isBeingPresented
                }
                fixture.controller.present(origin: .screen(fixture.context))
                try await fixture.wait("debugger presentation") {
                    fixture.modal.presentedViewController is PortholePresentationAnchor
                        .HostingController
                }
                let original = try #require(fixture.modal.presentedViewController)
                try await fixture
                    .wait("original debugger presentation completion") { !original.isBeingPresented
                    }
                fixture.controller.dismiss()
                fixture.controller.present(origin: .application(fixture.context.scope))
                let replacementID = try #require(fixture.controller.sessionID)
                try await fixture.wait("replacement debugger presentation") {
                    fixture.modal.presentedViewController != nil
                        && fixture.modal.presentedViewController !== original
                        && fixture.modal.presentedViewController?.isBeingPresented == false
                }
                #expect(fixture.controller.sessionID == replacementID)
                #expect(fixture.controller.origin == .application(fixture.context.scope))
                #expect(fixture.root.presentedViewController === fixture.modal)
                fixture.controller.dismiss()
                try await fixture
                    .wait("replacement debugger dismissal") {
                        fixture.modal.presentedViewController == nil
                    }
            } catch {
                await fixture.close()
                throw error
            }
            await fixture.close()
        }
    }
#endif
