import Foundation

public enum Flightradar24UsagePeriod: String, Hashable, Sendable {
    case last24Hours = "24h"
}

/// A usage-report limit that is separate from the live-position credit allowance.
public enum Flightradar24UsageError: Error, Equatable, Sendable {
    case rateLimited(retryAfterSeconds: Double?)
}

/// Account usage reported by FR24 for Throw's live full-position endpoint.
public struct Flightradar24UsageReport: Equatable, Sendable {
    public let period: Flightradar24UsagePeriod
    public let requestCount: Int
    public let credits: Int

    public init(period: Flightradar24UsagePeriod, requestCount: Int, credits: Int) {
        precondition(requestCount >= 0)
        precondition(credits >= 0)
        self.period = period
        self.requestCount = requestCount
        self.credits = credits
    }
}

/// A cadence projection based on the account's observed FR24 cost per request.
public struct Flightradar24CreditEstimate: Equatable, Sendable {
    public let averageCreditsPerRequest: Double
    public let creditsPerActiveHour: Double
    public let thirtyDayUpperBound: Double

    public init(
        averageCreditsPerRequest: Double,
        creditsPerActiveHour: Double,
        thirtyDayUpperBound: Double,
    ) {
        precondition(averageCreditsPerRequest >= 0)
        precondition(creditsPerActiveHour >= 0)
        precondition(thirtyDayUpperBound >= 0)
        self.averageCreditsPerRequest = averageCreditsPerRequest
        self.creditsPerActiveHour = creditsPerActiveHour
        self.thirtyDayUpperBound = thirtyDayUpperBound
    }
}

public enum Flightradar24CreditEstimator {
    public static func estimate(
        report: Flightradar24UsageReport,
        pollingInterval: PollingInterval,
        quietSchedule: QuietSchedule,
        requestMultiplicity: Flightradar24RequestMultiplicity,
    ) -> Flightradar24CreditEstimate? {
        guard report.requestCount > 0 else { return nil }
        let averageCreditsPerRequest = Double(report.credits) / Double(report.requestCount)
        let creditsPerActiveHour = averageCreditsPerRequest
            * (3600 / Double(pollingInterval.seconds))
            * Double(requestMultiplicity.rawValue)
        let quietMinutes = quietSchedule.interval?.durationMinutes ?? 0
        let activeHoursPerDay = Double(24 * 60 - quietMinutes) / 60
        return Flightradar24CreditEstimate(
            averageCreditsPerRequest: averageCreditsPerRequest,
            creditsPerActiveHour: creditsPerActiveHour,
            thirtyDayUpperBound: creditsPerActiveHour * activeHoursPerDay * 30,
        )
    }
}

enum Flightradar24UsageDecoder {
    static func decode(
        _ data: Data,
        period: Flightradar24UsagePeriod,
    ) throws -> Flightradar24UsageReport {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw Flightradar24DecodingError.invalidEnvelope
        }

        var requestCount = 0
        var credits = 0
        for entry in envelope.data where isLiveFullPositionEndpoint(entry.endpoint) {
            guard entry.requestCount >= 0, entry.credits >= 0 else {
                throw Flightradar24DecodingError.invalidEnvelope
            }
            let requestSum = requestCount.addingReportingOverflow(entry.requestCount)
            let creditSum = credits.addingReportingOverflow(entry.credits)
            guard requestSum.overflow == false, creditSum.overflow == false else {
                throw Flightradar24DecodingError.invalidEnvelope
            }
            requestCount = requestSum.partialValue
            credits = creditSum.partialValue
        }
        return Flightradar24UsageReport(
            period: period,
            requestCount: requestCount,
            credits: credits,
        )
    }

    private static func isLiveFullPositionEndpoint(_ endpoint: String) -> Bool {
        let path = endpoint.split(separator: "?", maxSplits: 1).first.map(String.init) ?? endpoint
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == "live/flight-positions/full"
    }
}

private struct Envelope: Decodable {
    let data: [Entry]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.data) else {
            data = []
            return
        }
        data = try container.decode([Entry].self, forKey: .data)
    }
}

private struct Entry: Decodable {
    let endpoint: String
    let requestCount: Int
    let credits: Int

    enum CodingKeys: String, CodingKey {
        case endpoint, credits
        case requestCount = "request_count"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        requestCount = try container.decode(ProviderInteger.self, forKey: .requestCount).value
        credits = try container.decode(ProviderInteger.self, forKey: .credits).value
    }
}

/// Matches the integer coercion used by FR24's official Pydantic response model.
private struct ProviderInteger: Decodable {
    let value: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
            return
        }
        if let value = try? container.decode(String.self),
           let integer = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            self.value = integer
            return
        }
        if let value = try? container.decode(Double.self),
           let integer = Int(exactly: value)
        {
            self.value = integer
            return
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected an integer-compatible provider value",
            ),
        )
    }
}
