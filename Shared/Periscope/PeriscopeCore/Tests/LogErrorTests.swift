import Foundation
import PeriscopeCore
import Testing

struct LogErrorTests {
    @Test func capturesExplicitCodableDetailsWithoutGuessing() throws {
        let original = CodableLogErrorTestFailure(attempt: 2, retryable: true)
        #expect(LogError(capturing: original).details == nil)
        let snapshot = try LogError(capturing: original, details: .encoding(original))
        #expect(snapshot.details == .object(["attempt": .int(2), "retryable": .bool(true)]))
    }

    @Test func explicitDetailsPropagateEncodingFailure() {
        let original = UnencodableLogErrorTestFailure()
        #expect(throws: UnencodableLogErrorTestFailure.EncodingFailure.self) {
            try LogError(capturing: original, details: .encoding(original))
        }
    }

    @Test func capturesDecodingPathAndUnderlyingCause() throws {
        struct Item: Decodable { let name: Int }
        do {
            _ = try JSONDecoder().decode(
                [Item].self,
                from: Data("[{\"name\":\"wrong type\"}]".utf8),
            )
            Issue.record("Expected a decoding error")
        } catch let error as DecodingError {
            let snapshot = LogError(capturing: error)
            let decoding = try #require(snapshot.decoding)
            #expect(decoding.kind == .typeMismatch)
            #expect(decoding.codingPath.count == 2)
            #expect(decoding.codingPath.first?.intValue == 0)
            #expect(decoding.codingPath.last?.stringValue == "name")
            #expect(try JSONDecoder()
                .decode(LogError.self, from: JSONEncoder().encode(snapshot)) == snapshot)
        }
        let cause = NSError(domain: "Parser", code: 9)
        let error = DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Invalid bytes",
            underlyingError: cause,
        ))
        let snapshot = LogError(capturing: error)
        #expect(snapshot.decoding?.kind == .dataCorrupted)
        #expect(snapshot.causes.first?.domain == "Parser")
    }

    @Test func capturesMissingKeyAndValueKinds() {
        let context = DecodingError.Context(
            codingPath: [LogErrorTestKey.items],
            debugDescription: "Missing",
        )
        let missingKey = LogError(capturing: DecodingError.keyNotFound(
            LogErrorTestKey.name,
            context,
        ))
        #expect(missingKey.decoding?.kind == .keyNotFound)
        #expect(missingKey.decoding?.codingPath.map(\.stringValue) == ["items", "name"])
        let missingValue = LogError(capturing: DecodingError.valueNotFound(Int.self, context))
        #expect(missingValue.decoding?.kind == .valueNotFound)
        #expect(missingValue.decoding?.codingPath.map(\.stringValue) == ["items"])
    }

    @Test func eventRetainsStructureButProjectionHasNoErrorValues() throws {
        let snapshot = LogError(capturing: LogErrorTestFailure())
        let event = LogErrorTestLog.Failed(error: .restricted(.errorDetails, snapshot))
        #expect(event.message == "Failed: Unavailable")
        #expect(event.classifiedFields == [.restricted(
            key: LogFieldKey("error"),
            kind: .errorDetails,
        )])
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(LogErrorTestLog.Failed.self, from: data)
        #expect(decoded.error == snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? Int == snapshot.code)
        #expect(error["description"] as? String == "Unavailable")
    }

    @Test func capturesTypedErrorAndExplicitDetails() throws {
        let original = NSError(domain: "Example", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Database unavailable",
            NSLocalizedFailureReasonErrorKey: "Connection closed",
            NSLocalizedRecoverySuggestionErrorKey: "Retry later",
            "secret": "must not copy userInfo",
        ])
        let snapshot = LogError(capturing: original, details: .object(["attempt": .int(3)]))
        #expect(snapshot.domain == "Example")
        #expect(snapshot.code == 42)
        #expect(snapshot.description == original.localizedDescription)
        #expect(snapshot.failureReason == "Connection closed")
        #expect(snapshot.recoverySuggestion == "Retry later")
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(LogError.self, from: encoded) == snapshot)
        let json = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(json == .object([
            "domain": .string("Example"),
            "code": .int(42),
            "description": .string("Database unavailable"),
            "failure_reason": .string("Connection closed"),
            "recovery_suggestion": .string("Retry later"),
            "causes": .array([]),
            "omitted_causes": .array([]),
            "details": .object(["attempt": .int(3)]),
        ]))
    }

    @Test func capturesSwiftLocalizedError() {
        let snapshot = LogError(capturing: LogErrorTestFailure())
        #expect(snapshot.description == "Unavailable")
        #expect(snapshot.failureReason == "Offline")
        #expect(snapshot.recoverySuggestion == "Reconnect")
        #expect(snapshot.details == nil)
    }

    @Test func capturesUnderlyingErrorTree() {
        let leaf = NSError(domain: "Leaf", code: 7)
        let root = NSError(domain: "Root", code: 1, userInfo: [
            NSUnderlyingErrorKey: leaf,
            NSMultipleUnderlyingErrorsKey: [NSError(domain: "Sibling", code: 2)],
        ])
        let snapshot = LogError(capturing: root)
        #expect(snapshot.causes.map(\.domain) == ["Leaf", "Sibling"])
        #expect(snapshot.causes.first?.code == 7)
        #expect(snapshot.omittedCauses.isEmpty)
    }

    @Test func boundsDepthAndMarksTruncation() {
        var error = NSError(domain: "Leaf", code: 0)
        for index in 1 ... 12 {
            error = NSError(domain: "Wrapper", code: index, userInfo: [NSUnderlyingErrorKey: error])
        }
        var snapshot = LogError(capturing: error)
        var count = 1
        while let cause = snapshot.causes.first {
            count += 1
            snapshot = cause
        }
        #expect(count == 8)
        #expect(snapshot.omittedCauses == [.depthLimit])
    }

    @Test func boundsTotalNodes() {
        let error = NSError(domain: "Root", code: 0, userInfo: [
            NSMultipleUnderlyingErrorsKey: (0 ..< 100).map { NSError(domain: "Leaf", code: $0) },
        ])
        let snapshot = LogError(capturing: error)
        #expect(snapshot.causes.count == 31)
        #expect(snapshot.omittedCauses == [.nodeLimit])
    }

    @Test func detectsCycles() {
        let snapshot = LogError(capturing: CyclicLogErrorTestFailure())
        #expect(snapshot.causes.isEmpty)
        #expect(snapshot.omittedCauses == [.cycle])
    }
}
