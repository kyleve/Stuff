import Foundation

/// Release destinations are configured by the host, independently of the data contract.
public enum AppUpdateAvailability: Sendable, Equatable {
    case noBuildsPublished
    case published(PublishedBuildLinks)
}

/// A published configuration always contains at least one supported distribution channel.
public enum PublishedBuildLinks: Sendable, Equatable {
    case testFlight(URL)
    case appStore(URL)
    case both(testFlight: URL, appStore: URL)
}
