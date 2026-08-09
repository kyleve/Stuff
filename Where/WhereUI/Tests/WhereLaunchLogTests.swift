import PeriscopeCore
import Testing
@testable import WhereUI

/// Pins the foreground diagnostic whose prior phase distinguishes a completed
/// headless drive from a launch still progressing when its scene appeared.
struct WhereLaunchLogTests {
    @Test func foregroundEntryRecordsThePriorRunnerState() {
        let event = WhereLaunchLog.foregroundEntered(
            trigger: "scene-became-active",
            previousReason: "undetermined",
            previousPhase: "ready",
        )

        #expect(event.level == .info)
        #expect(event.message == "Entered foreground (trigger: scene-became-active,"
            + " previous reason: undetermined,"
            + " previous phase: ready)")
    }
}
