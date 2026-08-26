import Foundation
import Testing
@testable import ThrowCore

struct Flightradar24UsageTests {
    @Test func missingDataCollectionIsAnEmptyReport() throws {
        let report = try Flightradar24UsageDecoder.decode(
            Data(#"{"metadata":{"period":"24h"}}"#.utf8),
            period: .last24Hours,
        )

        #expect(report.requestCount == 0)
        #expect(report.credits == 0)
    }

    @Test func decoderSumsOnlyLiveFullPositionUsage() throws {
        let data = Data(
            """
            {"data":[
              {"endpoint":"live/flight-positions/full?{filters}","request_count":12,"credits":2400},
              {"endpoint":"/live/flight-positions/full","request_count":3,"credits":480},
              {"endpoint":"static/airlines/light","request_count":9,"credits":9}
            ]}
            """.utf8,
        )

        let report = try Flightradar24UsageDecoder.decode(data, period: .last24Hours)

        #expect(report.requestCount == 15)
        #expect(report.credits == 2880)
    }

    @Test func decoderMatchesOfficialSDKIntegerCoercion() throws {
        let data = Data(
            """
            {"data":[
              {"endpoint":"live/flight-positions/full","request_count":"12","credits":"2400"},
              {"endpoint":"live/flight-positions/full","request_count":3.0,"credits":480.0}
            ]}
            """.utf8,
        )

        let report = try Flightradar24UsageDecoder.decode(data, period: .last24Hours)

        #expect(report.requestCount == 15)
        #expect(report.credits == 2880)
    }

    @Test(arguments: ["3.5", "true", "null", #""three""#])
    func decoderRejectsValuesThatAreNotIntegers(providerValue: String) {
        let data = Data(
            """
            {"data":[{
              "endpoint":"live/flight-positions/full",
              "request_count":1,
              "credits":\(providerValue)
            }]}
            """.utf8,
        )

        #expect(throws: Flightradar24DecodingError.invalidEnvelope) {
            try Flightradar24UsageDecoder.decode(data, period: .last24Hours)
        }
    }

    @Test func estimatorUsesObservedCostAndQuietSchedule() throws {
        let report = Flightradar24UsageReport(
            period: .last24Hours,
            requestCount: 12,
            credits: 2400,
        )
        let schedule = try QuietSchedule(
            start: LocalTime(hour: 22, minute: 0),
            end: LocalTime(hour: 6, minute: 0),
        )

        let estimate = try #require(
            Flightradar24CreditEstimator.estimate(
                report: report,
                pollingInterval: PollingInterval(seconds: 300),
                quietSchedule: schedule,
            ),
        )

        #expect(estimate.averageCreditsPerRequest == 200)
        #expect(estimate.creditsPerActiveHour == 2400)
        #expect(estimate.thirtyDayUpperBound == 1_152_000)
    }

    @Test func estimatorNeedsAtLeastOneRecentRequest() throws {
        let report = Flightradar24UsageReport(
            period: .last24Hours,
            requestCount: 0,
            credits: 0,
        )
        let pollingInterval = try PollingInterval(seconds: 300)

        #expect(
            Flightradar24CreditEstimator.estimate(
                report: report,
                pollingInterval: pollingInterval,
                quietSchedule: .disabled,
            ) == nil,
        )
    }
}
