import Foundation
import Testing
@testable import ThrowCore

struct ReadsbSourceTests {
    @Test(arguments: [(0.1, 0.5), (2.5, 2.5), (20.0, 10.0)])
    func clampsReceiverRefresh(refresh: Double, expected: Double) async throws {
        let transport = ScriptedHTTPTransport(
            outcomes: [
                .response(
                    ThrowCoreFixture.response(
                        data: Data("{\"refresh\":\(refresh)}".utf8),
                    ),
                ),
            ],
        )
        let source = try makeSource(transport: transport)
        let timing = try await source.recommendedPollingTiming()
        #expect(timing.intervalSeconds == expected)
        #expect(timing.metadataFailure == nil)
    }

    @Test func missingRefreshUsesOneSecond() async throws {
        let source = try makeSource(
            transport: ScriptedHTTPTransport(
                outcomes: [.response(ThrowCoreFixture.response(data: Data("{}".utf8)))],
            ),
        )
        let timing = try await source.recommendedPollingTiming()
        #expect(timing.intervalSeconds == 1)
    }

    @Test(arguments: ["nan", "inf", "-inf"])
    func nonFiniteRefreshFallsBackWithMetadataFailure(value: String) async throws {
        let source = try makeSource(
            transport: ScriptedHTTPTransport(
                outcomes: [
                    .response(
                        ThrowCoreFixture.response(
                            data: Data("{\"refresh\":\"\(value)\"}".utf8),
                        ),
                    ),
                ],
            ),
        )

        let timing = try await source.recommendedPollingTiming()
        #expect(timing.intervalSeconds == 1)
        #expect(timing.metadataFailure == .decoding)
    }

    @Test func metadataFailureDoesNotInvalidateUsableAircraftFeed() async throws {
        let transport = ScriptedHTTPTransport(
            outcomes: [
                .failure(HTTPTransportFailure(category: .offline)),
                .response(
                    ThrowCoreFixture.response(
                        data: Data("{\"now\":1700000000,\"aircraft\":[]}".utf8),
                    ),
                ),
            ],
        )
        let source = try makeSource(transport: transport)
        let timing = try await source.recommendedPollingTiming()
        #expect(timing.intervalSeconds == 1)
        #expect(timing.metadataFailure == .transport(.offline))
        let snapshot = try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        #expect(snapshot.observations.isEmpty)
        #expect(snapshot.successfulHTTPStatus == 200)
    }

    @Test func requestsSiblingMetadataAndThreeSecondTimeout() async throws {
        let transport = ScriptedHTTPTransport(
            outcomes: [.response(ThrowCoreFixture.response(data: Data("{}".utf8)))],
        )
        let source = try makeSource(transport: transport)
        _ = try await source.recommendedPollingTiming()
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.absoluteString == "http://receiver.local/data/receiver.json")
        #expect(request.timeoutSeconds == 3)
    }

    private func makeSource(transport: ScriptedHTTPTransport) throws -> ReadsbSource {
        try ReadsbSource(
            configuration: ReadsbConfiguration(
                aircraftJSONURL: #require(
                    URL(string: "http://receiver.local/data/aircraft.json"),
                ),
            ),
            transport: transport,
            decoder: ADSBExchangeV2Decoder(),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
    }
}
