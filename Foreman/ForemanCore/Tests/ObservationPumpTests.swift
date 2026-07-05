import ForemanCore
import Observation
import Testing

@MainActor
@Observable
private final class Model {
    var value = 0
}

@MainActor
struct ObservationPumpTests {
    @Test func firesOnEveryChangeNotJustTheFirst() async throws {
        let model = Model()
        var fires = 0
        let pump = ObservationPump(
            tracking: { _ = model.value },
            onChange: { fires += 1 },
        )
        defer { pump.cancel() }

        model.value = 1
        try await waitUntil("first change fires") { fires == 1 }

        // The interesting half: withObservationTracking is one-shot, so a
        // second notification proves the pump re-registered.
        model.value = 2
        try await waitUntil("second change fires") { fires == 2 }
    }

    @Test func cancelStopsNotifications() async throws {
        let model = Model()
        var cancelledFires = 0
        var controlFires = 0
        let cancelled = ObservationPump(
            tracking: { _ = model.value },
            onChange: { cancelledFires += 1 },
        )
        let control = ObservationPump(
            tracking: { _ = model.value },
            onChange: { controlFires += 1 },
        )
        defer { control.cancel() }

        cancelled.cancel()
        model.value = 1

        // Both pumps' notifications schedule main-actor tasks in FIFO order,
        // so once the control pump has fired, the cancelled pump's task has
        // also run (and must have declined).
        try await waitUntil("control pump fires") { controlFires == 1 }
        #expect(cancelledFires == 0)
    }

    @Test func changesBetweenNotificationAndReRegistrationAreCoalesced() async throws {
        let model = Model()
        var observed: [Int] = []
        let pump = ObservationPump(
            tracking: { _ = model.value },
            onChange: { observed.append(model.value) },
        )
        defer { pump.cancel() }

        // A synchronous burst lands before the deferred onChange runs: the
        // pump reports once, with the final value readable.
        model.value = 1
        model.value = 2
        model.value = 3
        try await waitUntil("burst reported") { !observed.isEmpty }
        #expect(observed == [3])
    }
}
