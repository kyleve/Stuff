import Foundation
@testable import PortholeCore
import Testing

struct PortholeMessagesTests {
    @Test func requestEnvelopeRoundTrips() throws {
        let envelopes: [PortholeRequestEnvelope] = [
            .init(id: 1, request: .hello(HelloRequest(clientName: "cli"))),
            .init(id: 2, request: .listConnectors),
            .init(id: 3, request: .invokeAction(
                ref: .init(connector: "app", action: "ping"),
                parameters: ["message": "hi"],
            )),
            .init(id: 4, request: .query(
                ref: .init(connector: "where", source: "year-report"),
                query: PortholeQuery(filters: ["year": 2026], limit: 50),
            )),
            .init(
                id: 5,
                request: .subscribe(ref: .init(connector: "periscope", source: "live-events")),
            ),
            .init(id: 6, request: .unsubscribe(subscriptionID: 99)),
            .init(id: 7, request: .ping),
        ]
        for envelope in envelopes {
            #expect(try jsonRoundTrip(envelope) == envelope)
        }
    }

    @Test func responseEnvelopeRoundTrips() throws {
        let manifest = ConnectorManifest(
            connector: .init(id: "app", title: "App", summary: "App info", version: 1),
            actions: [.init(
                id: "ping",
                title: "Ping",
                summary: "Echoes",
                parameters: .object([:]),
                isDestructive: false,
            )],
            dataSources: [],
        )
        let envelopes: [PortholeResponseEnvelope] = [
            .init(
                requestID: 1,
                response: .helloReply(HelloReply(
                    appName: "Where",
                    bundleID: "com.stuff.where",
                    deviceName: "iPhone",
                )),
            ),
            .init(requestID: 2, response: .connectors([manifest])),
            .init(requestID: 3, response: .actionResult(["ok": true])),
            .init(
                requestID: 4,
                response: .queryResult(PortholePage(rows: [["a": 1]], nextCursor: "c2")),
            ),
            .init(requestID: 5, response: .subscribed(subscriptionID: 7)),
            .init(requestID: nil, response: .event(subscriptionID: 7, value: ["tick": 1])),
            .init(requestID: 6, response: .failure(.notPaired)),
            .init(requestID: 7, response: .pong),
        ]
        for envelope in envelopes {
            #expect(try jsonRoundTrip(envelope) == envelope)
        }
    }

    @Test func errorsRoundTripWithAssociatedValues() throws {
        let errors: [PortholeError] = [
            .protocolMismatch(theirs: 2, ours: 1),
            .connectorNotFound("ghost"),
            .actionNotFound(.init(connector: "app", action: "nope")),
            .sourceNotFound(.init(connector: "app", source: "nope")),
            .invalidParameters("`year` is missing"),
            .subscriptionNotSupported(.init(connector: "app", source: "app-info")),
            .handlerFailed("boom"),
            .notPaired,
            .pairingFailed(.wrongCode),
            .frameTooLarge(1234),
        ]
        for error in errors {
            #expect(try jsonRoundTrip(error) == error)
        }
    }

    @Test func identifiersEncodeAsBareStrings() throws {
        let ref = PortholeActionRef(connector: "where", action: "scan-data-issues")
        let data = try JSONEncoder().encode(ref)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["connector"] as? String == "where")
        #expect(object?["action"] as? String == "scan-data-issues")
    }
}
