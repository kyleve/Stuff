@testable import Flagger
import Testing

struct FlaggerFailureTests {
    private enum FixtureError: Error {
        case failed
    }

    @Test
    func capturesTheAffectedFlagAndOperation() {
        let id = FlagID(rawValue: "flag")
        let failure = FlaggerFailure(flagID: id, operation: .write, error: FixtureError.failed)

        #expect(failure.flagID == id)
        #expect(failure.operation == .write)
        #expect(failure.message.contains("failed"))
    }
}
