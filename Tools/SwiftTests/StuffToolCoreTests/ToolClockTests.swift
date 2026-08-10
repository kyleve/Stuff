import Foundation
import StuffToolCore
import Testing

struct ToolClockTests {
    @Test func sleepPropagatesCancellation() async {
        let task = Task {
            try await ContinuousToolClock().sleep(for: .seconds(60))
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func reportsWallTime() {
        let before = Date()
        let reported = ContinuousToolClock().date()
        let after = Date()

        #expect(reported >= before)
        #expect(reported <= after)
    }
}
