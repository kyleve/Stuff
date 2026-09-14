@testable import PortholeUI
import Testing

#if canImport(UIKit)
    @MainActor
    struct PortholeHostingSnapshotFixtureTests {
        @Test func disabledPreparationKeepsTheHostInactive() async {
            let fixture = PortholeHostingSnapshotFixture(activate: false)
            await fixture.prepare()
            #expect(fixture.model.activeSession == nil)
            if case .disabled = fixture.model.state {} else {
                Issue.record("The disabled fixture changed activation state.")
            }
        }

        @Test func preparationIsSharedAcrossCaptureHooksAndViewReattachment() async throws {
            let fixture = PortholeHostingSnapshotFixture(activate: true)
            async let measurement: Void = fixture.prepare()
            async let content: Void = fixture.prepare()
            await measurement
            await content
            let session = try #require(fixture.model.activeSession)
            guard case let .invitation(invitation) = session.enrollment else {
                Issue.record("Preparation completed before the invitation was ready.")
                return
            }
            #expect(!invitation.text.isEmpty)
            #expect(invitation.image != nil)
            #expect(session.peers.count == 1)
            await fixture.prepare()
            #expect(fixture.model.activeSession?.id == session.id)
            guard case let .invitation(repeated) = session.enrollment else {
                Issue.record("Reattachment replaced the ready invitation.")
                return
            }
            #expect(repeated.text == invitation.text)
            await session.cancelInvitation()
            await fixture.prepare()
            if case .closed = session.enrollment {} else {
                Issue.record("A repeated capture task restarted enrollment after it was closed.")
            }
            await fixture.model.disable()
            #expect(fixture.model.activeSession == nil)
        }

        @Test func cancelledCaptureWaiterDoesNotCancelSharedPreparation() async throws {
            let fixture = PortholeHostingSnapshotFixture(activate: true)
            let waiter = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                await fixture.prepare()
            }
            await waiter.value
            await fixture.prepare()
            let session = try #require(fixture.model.activeSession)
            if case .invitation = session.enrollment {} else {
                Issue.record("A cancelled view task cancelled the shared fixture preparation.")
            }
            await fixture.model.disable()
        }
    }
#endif
