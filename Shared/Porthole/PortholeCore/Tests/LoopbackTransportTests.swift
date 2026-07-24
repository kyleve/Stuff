import Foundation
@testable import PortholeCore
import Testing

struct LoopbackTransportTests {
    @Test func framesDeliverToThePeer() async throws {
        let (a, b) = LoopbackTransport.makePair()
        try await a.send(Data("ping".utf8))
        #expect(try await firstFrame(from: b) == Data("ping".utf8))

        try await b.send(Data("pong".utf8))
        #expect(try await firstFrame(from: a) == Data("pong".utf8))
    }

    @Test func closingEndsThePeerStream() async throws {
        let (a, b) = LoopbackTransport.makePair()
        await a.close()

        try await withTimeout {
            var iterator = b.incoming.makeAsyncIterator()
            let next = try await iterator.next()
            #expect(next == nil) // finished, not a value
        }
    }

    @Test func sendingOnAClosedTransportThrows() async throws {
        let (a, _) = LoopbackTransport.makePair()
        await a.close()
        await #expect(throws: PortholeTransportError.self) {
            try await a.send(Data("late".utf8))
        }
    }
}
