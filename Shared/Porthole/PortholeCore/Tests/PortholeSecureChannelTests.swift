import CryptoKit
import Foundation
@testable import PortholeCore
import Testing

struct PortholeSecureChannelTests {
    @Test func roundTripsPlaintextInBothDirections() async throws {
        let key = SymmetricKey(size: .bits256)
        let (rawClient, rawDevice) = LoopbackTransport.makePair()
        let client = PortholeSecureChannel(wrapping: rawClient, key: key, role: .client)
        let device = PortholeSecureChannel(wrapping: rawDevice, key: key, role: .device)

        try await client.send(Data("request".utf8))
        #expect(try await firstFrame(from: device) == Data("request".utf8))

        try await device.send(Data("response".utf8))
        #expect(try await firstFrame(from: client) == Data("response".utf8))
    }

    @Test func multipleFramesDecryptInOrder() async throws {
        let key = SymmetricKey(size: .bits256)
        let (rawClient, rawDevice) = LoopbackTransport.makePair()
        let client = PortholeSecureChannel(wrapping: rawClient, key: key, role: .client)
        let device = PortholeSecureChannel(wrapping: rawDevice, key: key, role: .device)

        for index in 0 ..< 5 {
            try await client.send(Data("f\(index)".utf8))
        }

        try await withTimeout {
            var iterator = device.incoming.makeAsyncIterator()
            for index in 0 ..< 5 {
                let frame = try await iterator.next()
                #expect(frame == Data("f\(index)".utf8))
            }
        }
    }

    @Test func aTamperedFrameFailsToOpenAndEndsTheStream() async throws {
        let key = SymmetricKey(size: .bits256)
        let (rawClient, rawDevice) = LoopbackTransport.makePair()
        let device = PortholeSecureChannel(wrapping: rawDevice, key: key, role: .device)

        // Feed the device raw garbage instead of a validly sealed frame.
        try await rawClient.send(Data("not a valid sealed frame".utf8))

        await #expect(throws: (any Error).self) {
            try await withTimeout {
                var iterator = device.incoming.makeAsyncIterator()
                _ = try await iterator.next()
            }
        }
    }

    @Test func aReplayedFrameIsRejected() async throws {
        let key = SymmetricKey(size: .bits256)

        // Capture one genuinely-sealed frame (counter 0) from a client channel.
        let (rawClient, rawDeviceObserver) = LoopbackTransport.makePair()
        let client = PortholeSecureChannel(wrapping: rawClient, key: key, role: .client)
        try await client.send(Data("payload".utf8))
        let sealed = try await firstFrame(from: rawDeviceObserver)

        // Deliver it twice to a fresh device channel: the first opens (counter 0),
        // the replay expects counter 1 and must fail.
        let (rawInjector, rawDevice) = LoopbackTransport.makePair()
        let device = PortholeSecureChannel(wrapping: rawDevice, key: key, role: .device)

        try await withTimeout {
            var iterator = device.incoming.makeAsyncIterator()
            try await rawInjector.send(sealed)
            #expect(try await iterator.next() == Data("payload".utf8))

            try await rawInjector.send(sealed)
            await #expect(throws: (any Error).self) {
                _ = try await iterator.next()
            }
        }
    }

    @Test func theWrongKeyFailsToOpen() async throws {
        let (rawClient, rawDevice) = LoopbackTransport.makePair()
        let client = PortholeSecureChannel(
            wrapping: rawClient,
            key: SymmetricKey(size: .bits256),
            role: .client,
        )
        let device = PortholeSecureChannel(
            wrapping: rawDevice,
            key: SymmetricKey(size: .bits256),
            role: .device,
        )

        try await client.send(Data("secret".utf8))
        await #expect(throws: (any Error).self) {
            try await withTimeout {
                var iterator = device.incoming.makeAsyncIterator()
                _ = try await iterator.next()
            }
        }
    }
}
