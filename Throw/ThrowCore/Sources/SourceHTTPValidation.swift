import Foundation

enum SourceHTTPValidation {
    static func validate(
        _ response: HTTPResponse,
        source: AircraftSourceKind,
        receivedAt: Date,
    ) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            let retryAfter = retryAfterSeconds(response: response, receivedAt: receivedAt)
            switch (source, response.statusCode) {
                case (.adsbExchangeRapidAPI, 401):
                    throw AircraftSourceFailure.invalidCredential
                case (.adsbExchangeRapidAPI, 402):
                    throw AircraftSourceFailure.subscriptionRequired
                case (.adsbExchangeRapidAPI, 403):
                    throw AircraftSourceFailure.entitlementRejected
                case (_, 429):
                    throw AircraftSourceFailure.quotaReached(retryAfterSeconds: retryAfter)
                case let (_, statusCode):
                    throw AircraftSourceFailure.provider(
                        statusCode: statusCode,
                        retryAfterSeconds: retryAfter,
                    )
            }
        }
    }

    private static func retryAfterSeconds(
        response: HTTPResponse,
        receivedAt: Date,
    ) -> Double? {
        guard let value = response.headerValue(for: "Retry-After") else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(normalizedValue), seconds.isFinite, seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: normalizedValue) else { return nil }
        return max(0, date.timeIntervalSince(receivedAt))
    }
}
