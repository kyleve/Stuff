import Foundation
@testable import PortholeCore

/// Encodes then decodes `value` as JSON — the round-trip the real wire performs.
func jsonRoundTrip<T: Codable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

/// Round-trips a `PortholeValue` nested inside an object, so scalars don't rely
/// on top-level JSON-fragment support and the test mirrors real (always-nested)
/// wire use.
func wireRoundTrip(_ value: PortholeValue) throws -> PortholeValue {
    let wrapped = PortholeValue.object(["v": value])
    let data = try JSONEncoder().encode(wrapped)
    let decoded = try JSONDecoder().decode(PortholeValue.self, from: data)
    guard let inner = decoded["v"] else {
        throw WireRoundTripError.missingValue
    }
    return inner
}

/// The raw JSON object a `PortholeValue` encodes to, for shape assertions.
func jsonObject(_ value: PortholeValue) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        throw WireRoundTripError.notAnObject
    }
    return dictionary
}

enum WireRoundTripError: Error {
    case missingValue
    case notAnObject
}

struct TimeoutError: Error {}

/// Runs `operation` with a wall-clock ceiling so a stuck async read fails the
/// test instead of hanging the suite.
func withTimeout<T: Sendable>(
    _ duration: Duration = .seconds(2),
    _ operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// Awaits the first frame delivered to a transport's `incoming`, with a timeout.
func firstFrame(from transport: some PortholeTransport) async throws -> Data {
    try await withTimeout {
        var iterator = transport.incoming.makeAsyncIterator()
        guard let frame = try await iterator.next() else { throw TimeoutError() }
        return frame
    }
}
