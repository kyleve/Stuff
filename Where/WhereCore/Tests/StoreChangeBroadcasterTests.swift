import Foundation
import Testing
@testable import WhereCore

struct StoreChangeBroadcasterTests {
    /// A ping sent after subscribing is delivered (the stream buffers the
    /// newest pending value, so iterating after `send()` still sees it).
    @Test func sendReachesActiveSubscriber() async {
        let broadcaster = StoreChangeBroadcaster()
        let stream = broadcaster.subscribe()

        broadcaster.send()

        var received = false
        for await _ in stream {
            received = true
            break
        }
        #expect(received)
    }

    /// Every subscriber gets its own independent stream — one consumer
    /// iterating (and breaking) doesn't starve or finish another's.
    @Test func eachSubscriberReceivesItsOwnPing() async {
        let broadcaster = StoreChangeBroadcaster()
        let first = broadcaster.subscribe()
        let second = broadcaster.subscribe()

        broadcaster.send()

        var firstReceived = false
        for await _ in first {
            firstReceived = true
            break
        }
        var secondReceived = false
        for await _ in second {
            secondReceived = true
            break
        }
        #expect(firstReceived)
        #expect(secondReceived)
    }

    /// `finishAll()` ends every subscriber's stream, so iteration completes
    /// without another ping.
    @Test func finishAllEndsSubscriberStreams() async {
        let broadcaster = StoreChangeBroadcaster()
        let stream = broadcaster.subscribe()

        broadcaster.finishAll()

        var pingCount = 0
        for await _ in stream {
            pingCount += 1
        }
        #expect(pingCount == 0)
    }
}
