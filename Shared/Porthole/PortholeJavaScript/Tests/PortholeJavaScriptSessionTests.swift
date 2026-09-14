import Foundation
import PortholeCore
import PortholeJavaScript
import Synchronization
import Testing

struct PortholeJavaScriptSessionTests {
    @Test func preservesExactNativeWholeDoubleAcrossExponentNotation() async throws {
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { _, _ in .number(1e18) },
            events: { _ in },
        )
        let result = try await session.execute(source: """
        const result = await porthole.call("wholeDouble", null);
        [typeof result, result]
        """)
        #expect(result == .array([.string("bigint"), .number(1e18)]))
    }

    @Test func preservesUInt64BigIntAndRejectsOutOfRangeValues() async throws {
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        let result = try await session.execute(source: """
        const result = await porthole.call("echo", {maximum: 18446744073709551615n});
        [typeof result.maximum, result.maximum, result.maximum - 1n]
        """)
        #expect(result == .array([
            .string("bigint"),
            .unsignedInteger(.max),
            .unsignedInteger(.max - 1),
        ]))
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "18446744073709551616n")
        }
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "-9223372036854775809n")
        }
    }

    @Test func rejectsUnsafeNumberArgumentsBeforeNativeExecution() async {
        let calls = Mutex(0)
        let session = PortholeJavaScriptSession(limits: .interactive, nativeCall: { _, value in
            calls.withLock { $0 += 1 }
            return value
        }, events: { _ in })
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "await porthole.call('echo', 9007199254740993)")
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func awaitsNativeCallsAndPreservesInt64() async throws {
        let events = Mutex<[PortholeJavaScriptEvent]>([])
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { name, arguments in
                #expect(name == "echo")
                #expect(arguments["large"] == .integer(.max))
                return arguments
            },
            events: { event in events.withLock { $0.append(event) } },
        )
        let value = try await session.execute(source: """
        const result = await porthole.call("echo", {large: 9223372036854775807n});
        [typeof result.large, result.large, result.large - 1n]
        """)
        #expect(value == .array([.string("bigint"), .integer(.max), .integer(.max - 1)]))
        let recorded = events.withLock { $0 }
        #expect(recorded.count == 4)
        guard case .started = recorded.first, case .finished = recorded.last else {
            Issue.record("Expected one complete console event sequence")
            return
        }
    }

    @Test func runsParallelNativePromises() async throws {
        let session = PortholeJavaScriptSession(limits: .interactive, nativeCall: { _, value in
            await Task.yield()
            return value
        }, events: { _ in })
        let result = try await session.execute(source: """
        await Promise.all([porthole.call("echo", 1), porthole.call("echo", 2)])
        """)
        #expect(result == .array([.integer(1), .integer(2)]))
    }

    @Test func resetsBindingsBetweenCommands() async throws {
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        #expect(try await session.execute(source: "globalThis.saved = 4") == .integer(4))
        #expect(try await session.execute(source: "typeof saved") == .string("undefined"))
        #expect(try await session.execute(source: "let empty = 4;") == .null)
    }

    @Test func excludesHostAndNetworkGlobals() async throws {
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        let result = try await session
            .execute(
                source: "[typeof std, typeof os, typeof require, typeof fetch, typeof process]",
            )
        #expect(result == .array(Array(repeating: .string("undefined"), count: 5)))
    }

    @Test(arguments: ["while (true) {}", "await new Promise(() => {})"])
    func expiresRunningAndPendingScripts(source: String) async {
        var limits = PortholeJavaScriptLimits.interactive
        limits.duration = .milliseconds(50)
        let session = PortholeJavaScriptSession(
            limits: limits,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        await #expect(throws: PortholeJavaScriptError.timedOut) {
            try await session.execute(source: source)
        }
    }

    @Test(.timeLimit(.minutes(1))) func rejectsConcurrentCommandsAndCancelsLoop() async throws {
        let events = AsyncStream.makeStream(of: PortholeJavaScriptEvent.self)
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { _, value in value },
            events: {
                events.continuation.yield($0)
            },
        )
        let running = Task { try await session.execute(source: "while (true) {}") }
        var iterator = events.stream.makeAsyncIterator()
        guard case .started = await iterator.next() else {
            Issue.record("Expected execution to start")
            running.cancel()
            return
        }
        await #expect(throws: PortholeJavaScriptError.busy) {
            try await session.execute(source: "1")
        }
        session.cancel()
        await #expect(throws: PortholeJavaScriptError.cancelled) { try await running.value }
        #expect(try await session.execute(source: "2") == .integer(2))
    }

    @Test(.timeLimit(.minutes(1))) func taskCancellationReachesNativeOperation() async throws {
        let events = AsyncStream.makeStream(of: PortholeJavaScriptEvent.self)
        let nativeStarted = AsyncStream.makeStream(of: Bool.self)
        let nativeCancelled = AsyncStream.makeStream(of: Bool.self)
        let session = PortholeJavaScriptSession(limits: .interactive, nativeCall: { _, _ in
            do {
                nativeStarted.continuation.yield(true)
                // A suspended operation lets this test observe native task cancellation.
                try await Task.sleep(for: .seconds(3600))
                Issue.record("The native operation completed without cancellation")
                return .null
            } catch {
                nativeCancelled.continuation.yield(error is CancellationError)
                throw error
            }
        }, events: { events.continuation.yield($0) })
        let running = Task { try await session.execute(source: "await porthole.call('wait', null)")
        }
        var started = nativeStarted.stream.makeAsyncIterator()
        #expect(await started.next() == true)
        running.cancel()
        await #expect(throws: PortholeJavaScriptError.cancelled) { try await running.value }
        var cancellation = nativeCancelled.stream.makeAsyncIterator()
        #expect(await cancellation.next() == true)
    }

    @Test func nativeFailureIsCatchable() async throws {
        let session = PortholeJavaScriptSession(limits: .interactive, nativeCall: { _, _ in
            throw PortholeJavaScriptError.valueTooLarge
        }, events: { _ in })
        #expect(try await session
            .execute(
                source: "try { await porthole.call('fail', null); } catch (e) { String(e); }",
            ) ==
            .string("valueTooLarge"))
    }

    @Test(arguments: [
        "({notJSON: NaN})",
        "({notJSON: undefined})",
        "18446744073709551616n",
        "const x = {}; x.x = x; x",
        "function () {",
    ])
    func surfacesInvalidResultsAndSyntax(source: String) async {
        let session = PortholeJavaScriptSession(
            limits: .interactive,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        await #expect(throws: (any Error).self) { try await session.execute(source: source) }
    }

    @Test func boundsNativeCallsAndValueSize() async {
        var limits = PortholeJavaScriptLimits.interactive
        limits.nativeCalls = 1
        limits.valueBytes = 64
        let session = PortholeJavaScriptSession(
            limits: limits,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        await #expect(throws: (any Error).self) {
            try await session
                .execute(source: "await porthole.call('echo', 1); await porthole.call('echo', 2)")
        }
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "'x'.repeat(100)")
        }
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "await porthole.call('echo', 'x'.repeat(100))")
        }
    }

    @Test func boundsHeapAndStack() async throws {
        var limits = PortholeJavaScriptLimits.interactive
        limits.heapBytes = 2 * 1024 * 1024
        let session = PortholeJavaScriptSession(
            limits: limits,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "new ArrayBuffer(10 * 1024 * 1024)")
        }
        await #expect(throws: (any Error).self) {
            try await session.execute(source: "function f() { return 1 + f(); } f()")
        }
        #expect(try await session.execute(source: "1 + 1") == .integer(2))
    }
}
