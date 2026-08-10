import Darwin
import StuffToolCore
import Testing

struct ProcessInspectorTests {
    @Test func findsTheCurrentProcessAndRejectsAnInvalidPID() {
        let inspector = SystemProcessInspector()

        #expect(inspector.isRunning(processID: getpid()))
        #expect(inspector.isRunning(processID: Int32.max) == false)
    }
}
