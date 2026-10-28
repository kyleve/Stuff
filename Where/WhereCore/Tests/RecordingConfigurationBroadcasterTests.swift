import Testing
@testable import WhereCore

struct RecordingConfigurationBroadcasterTests {
    @Test func eachSubscriberReceivesTheSameRuntimeUpdate() async {
        let broadcaster = RecordingConfigurationBroadcaster()
        var first = broadcaster.subscribe().makeAsyncIterator()
        var second = broadcaster.subscribe().makeAsyncIterator()
        let update = RecordingDeviceRuntimeUpdate(sequence: 1, state: .unavailable)

        broadcaster.send(update)

        #expect(await first.next() == update)
        #expect(await second.next() == update)
        broadcaster.finishAll()
    }

    @Test func aSlowSubscriberKeepsOnlyTheNewestRuntimeUpdate() async {
        let broadcaster = RecordingConfigurationBroadcaster()
        var iterator = broadcaster.subscribe().makeAsyncIterator()
        let older = RecordingDeviceRuntimeUpdate(sequence: 1, state: .unavailable)
        let newest = RecordingDeviceRuntimeUpdate(sequence: 2, state: .unavailable)

        broadcaster.send(older)
        broadcaster.send(newest)

        #expect(await iterator.next() == newest)
        broadcaster.finishAll()
    }

    @Test func finishAllEndsEveryExistingSubscription() async {
        let broadcaster = RecordingConfigurationBroadcaster()
        var first = broadcaster.subscribe().makeAsyncIterator()
        var second = broadcaster.subscribe().makeAsyncIterator()

        broadcaster.finishAll()

        #expect(await first.next() == nil)
        #expect(await second.next() == nil)
    }
}
