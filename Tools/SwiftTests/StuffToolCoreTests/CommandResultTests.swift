import StuffToolCore
import Subprocess
import Testing

struct CommandResultTests {
    @Test func successAndLossyTextViewsDoNotDiscardTheOriginalBytes() {
        let result = CommandResult(
            terminationStatus: .exited(0),
            standardOutput: [102, 111, 111, 255],
            standardError: [],
        )

        #expect(result.succeeded)
        #expect(result.standardOutputText == "foo�")
        #expect(result.standardOutput == [102, 111, 111, 255])
    }

    @Test func convertsSignalsToShellCompatibleExitCodes() {
        let result = CommandResult(
            terminationStatus: .signaled(9),
            standardOutput: [],
            standardError: [],
        )

        #expect(result.exitCode == 137)
        #expect(result.succeeded == false)
    }
}
