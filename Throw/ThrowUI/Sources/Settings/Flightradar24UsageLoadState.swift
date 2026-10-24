import ThrowCore

enum Flightradar24UsageLoadState: Equatable {
    case idle
    case loading
    case loaded(Flightradar24UsageReport)
    case rateLimited
    case unexpectedResponse
    case failed(ThrowFailureCategory)
}
