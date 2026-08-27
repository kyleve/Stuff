import Foundation
import Testing
@testable import ThrowCore

struct Flightradar24RequestFactoryTests {
    enum DatelineSide: CaseIterable, CustomTestStringConvertible {
        case east
        case west

        var testDescription: String {
            switch self {
                case .east: "east"
                case .west: "west"
            }
        }

        var longitude: Double {
            switch self {
                case .east: 179.8
                case .west: -179.8
            }
        }

        var expectedWesternBounds: String {
            switch self {
                case .east: "1.000,-1.000,-180.000,-179.200"
                case .west: "1.000,-1.000,-180.000,-178.800"
            }
        }

        var expectedEasternBounds: String {
            switch self {
                case .east: "1.000,-1.000,178.800,180.000"
                case .west: "1.000,-1.000,179.200,180.000"
            }
        }
    }

    @Test func liveRequestUsesBearerContractAndCoarseBounds() throws {
        let token = "fr24-secret-token"
        let plan = try requestFactory(token: token).livePositionPlan(
            for: ThrowCoreFixture.mapQuery(radius: 5),
        )
        guard case let .single(request) = plan else {
            Issue.record("A San Francisco query must use one FR24 request")
            return
        }

        #expect(request.url.host() == "fr24api.flightradar24.com")
        #expect(request.url.path() == "/api/live/flight-positions/full")
        #expect(request.url.query()?.contains("bounds=") == true)
        #expect(request.url.absoluteString.contains(token) == false)
        #expect(request.headers[.acceptVersion] == "v1")
        #expect(request.headers[.authorization] == "Bearer \(token)")
        #expect(request.timeoutSeconds == 8)
    }

    @Test(arguments: DatelineSide.allCases)
    func antimeridianBoundsSplitIntoTwoValidRequests(side: DatelineSide) throws {
        let query = try ThrowCoreFixture.datelineMapQuery(longitude: side.longitude)
        let plan = try requestFactory(token: "token").livePositionPlan(for: query)
        guard case let .antimeridian(western, eastern) = plan else {
            Issue.record("An antimeridian query must use two FR24 requests")
            return
        }

        #expect(try bounds(in: western) == side.expectedWesternBounds)
        #expect(try bounds(in: eastern) == side.expectedEasternBounds)
        #expect(western.headers[.authorization] == "Bearer token")
        #expect(eastern.headers[.authorization] == "Bearer token")
        #expect(try Flightradar24RequestMultiplicity.livePosition(for: query) == .antimeridian)
    }

    @Test func polarQueryUsesOneFullLongitudeRequest() throws {
        let observer = try ThrowCoreFixture.observer(latitude: 89, longitude: 179)
        let query = try AircraftQuery(
            observer: observer,
            center: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 240))),
            includeGroundAircraft: false,
        )
        let plan = try requestFactory(token: "token").livePositionPlan(for: query)
        guard case let .single(request) = plan else {
            Issue.record("A full-longitude query must use one FR24 request")
            return
        }

        #expect(try bounds(in: request) == "90.000,84.833,-180.000,180.000")
        #expect(try Flightradar24RequestMultiplicity.livePosition(for: query) == .single)
    }

    @Test func usageRequestUsesBearerContractAndPeriod() throws {
        let token = "fr24-secret-token"
        let request = try requestFactory(token: token).usageRequest(period: .last24Hours)

        #expect(request.url.path() == "/api/usage")
        #expect(request.url.query() == "period=24h")
        #expect(request.url.absoluteString.contains(token) == false)
        #expect(request.headers[.acceptVersion] == "v1")
        #expect(request.headers[.authorization] == "Bearer \(token)")
        #expect(request.timeoutSeconds == 8)
    }

    private func requestFactory(token: String) throws -> Flightradar24RequestFactory {
        try Flightradar24RequestFactory(
            baseURL: Flightradar24Source.baseURL,
            credential: AircraftCredential(secret: token),
        )
    }

    private func bounds(in request: HTTPRequest) throws -> String {
        let components = try #require(URLComponents(
            url: request.url,
            resolvingAgainstBaseURL: false,
        ))
        return try #require(components.queryItems?.first { $0.name == "bounds" }?.value)
    }
}
