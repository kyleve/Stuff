import Foundation
import PortholeCore
import PortholeKit
import RegionKit
import WhereCore

/// A Sendable snapshot of the app's preferences, so the connector can expose
/// them (and use the drift threshold for scans) without capturing the
/// non-Sendable `WherePreferences` in its handlers.
public struct WherePreferencesSnapshot: Sendable {
    public var hasOnboarded: Bool
    public var wantsTracking: Bool
    public var remindersEnabled: Bool
    public var summaryEnabled: Bool
    public var issueAlertsEnabled: Bool
    public var driftThresholdMeters: Int

    public init(
        hasOnboarded: Bool,
        wantsTracking: Bool,
        remindersEnabled: Bool,
        summaryEnabled: Bool,
        issueAlertsEnabled: Bool,
        driftThresholdMeters: Int,
    ) {
        self.hasOnboarded = hasOnboarded
        self.wantsTracking = wantsTracking
        self.remindersEnabled = remindersEnabled
        self.summaryEnabled = summaryEnabled
        self.issueAlertsEnabled = issueAlertsEnabled
        self.driftThresholdMeters = driftThresholdMeters
    }
}

/// The Where feature's Porthole connector (id `where`): read-mostly access to
/// year reports, manual days, evidence metadata, preferences, and data issues,
/// plus a couple of safe actions — everything through the existing
/// `WhereServices` collaborators. No new domain logic and no destructive
/// actions in v1.
public final class WhereConnector: PortholeConnector {
    public let descriptor = PortholeConnectorDescriptor(
        id: "where",
        title: "Where",
        summary: "Residency data: year reports, manual days, evidence, preferences, and data issues.",
        version: 1,
    )

    private let services: WhereServices
    private let preferences: WherePreferencesSnapshot

    public init(services: WhereServices, preferences: WherePreferencesSnapshot) {
        self.services = services
        self.preferences = preferences
    }

    public func actions() -> [PortholeAction] {
        let services = services
        let preferences = preferences
        return [
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "scan-data-issues",
                    title: "Scan data issues",
                    summary: "Force a fresh data-quality scan for a year and return issue counts by category.",
                    parameters: .object(["year": .integer("Gregorian year")], required: ["year"]),
                    isDestructive: false,
                ),
                handler: { parameters in
                    let year = Int(parameters["year"]?.intValue ?? 0)
                    let report = try await services.reports.yearReport(for: year)
                    let issues = try await services.resolution.issues(
                        year: year,
                        primaryRegions: Region.primaryRegions(in: report.totals),
                        driftThresholdMeters: Double(preferences.driftThresholdMeters),
                        force: true,
                    )
                    return .object(Self.issueCounts(issues))
                },
            ),
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "capture-location-now",
                    title: "Capture location now",
                    summary: "Take a one-shot GPS fix and return the sample, or null if none is available.",
                    parameters: .object([:]),
                    isDestructive: false,
                ),
                handler: { _ in
                    guard let sample = await services.ingestor.currentLocation()
                    else { return .null }
                    return Self.sampleRow(sample)
                },
            ),
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "attribute-coordinate",
                    title: "Attribute coordinate",
                    summary: "Return the region a latitude/longitude falls in.",
                    parameters: .object([
                        "latitude": .number("Degrees"),
                        "longitude": .number("Degrees"),
                    ], required: ["latitude", "longitude"]),
                    isDestructive: false,
                ),
                handler: { parameters in
                    guard let latitude = parameters["latitude"]?.doubleValue,
                          let longitude = parameters["longitude"]?.doubleValue
                    else {
                        throw PortholeError
                            .invalidParameters("latitude and longitude are required")
                    }
                    let region = RegionAttributor.all.region(
                        at: Coordinate(latitude: latitude, longitude: longitude),
                    )
                    return .object([
                        "region": .string(region.rawValue),
                        "name": .string(region.localizedName),
                    ])
                },
            ),
        ]
    }

    public func dataSources() -> [PortholeDataSource] {
        let services = services
        let preferences = preferences
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "year-report",
                    title: "Year report",
                    summary: "Per-region day counts for a year.",
                    rowSchema: .object([
                        "region": .string(),
                        "name": .string(),
                        "days": .integer(),
                    ]),
                    filters: .object(["year": .integer("Gregorian year")], required: ["year"]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    let year = try Self.year(query.filters)
                    let report = try await services.reports.yearReport(for: year)
                    let rows = report.totals
                        .sorted { $0.value > $1.value }
                        .map { region, days in
                            PortholeValue.object([
                                "region": .string(region.rawValue),
                                "name": .string(region.localizedName),
                                "days": .int(Int64(days)),
                            ])
                        }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "manual-days",
                    title: "Manual days",
                    summary: "User-asserted day entries for a year.",
                    rowSchema: .object([
                        "day": .string(),
                        "regions": .array(of: .string()),
                        "isAuthoritative": .boolean(),
                    ]),
                    filters: .object(["year": .integer("Gregorian year")], required: ["year"]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    let year = try Self.year(query.filters)
                    let days = try await services.reports.manualDays(inYear: year)
                    let rows = days.map { presence in
                        PortholeValue.object([
                            "day": .string(String(describing: presence.day)),
                            "regions": .array(presence.regions.map { .string($0.rawValue) }),
                            "isAuthoritative": .bool(presence.isAuthoritative),
                        ])
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "evidence",
                    title: "Evidence",
                    summary: "Metadata for user-attached evidence in a year (no blob bytes).",
                    rowSchema: .object([
                        "id": .string(),
                        "kind": .string(),
                        "capturedAt": .date(),
                        "region": .string(),
                        "note": .string(),
                    ]),
                    filters: .object(["year": .integer("Gregorian year")], required: ["year"]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    let year = try Self.year(query.filters)
                    let evidence = try await services.evidence.list(for: year)
                    let rows = evidence.map { item -> PortholeValue in
                        var object: [String: PortholeValue] = [
                            "id": .string(item.id.uuidString),
                            "kind": .string(String(describing: item.kind)),
                            "capturedAt": .date(item.capturedAt),
                        ]
                        if let region = item.region { object["region"] = .string(region.rawValue) }
                        if let note = item.note { object["note"] = .string(note) }
                        return .object(object)
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "preferences",
                    title: "Preferences",
                    summary: "A single-row snapshot of the app's preferences.",
                    rowSchema: .object([
                        "hasOnboarded": .boolean(),
                        "wantsTracking": .boolean(),
                        "remindersEnabled": .boolean(),
                        "summaryEnabled": .boolean(),
                        "issueAlertsEnabled": .boolean(),
                        "driftThresholdMeters": .integer(),
                    ]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in
                    PortholePage(rows: [.object([
                        "hasOnboarded": .bool(preferences.hasOnboarded),
                        "wantsTracking": .bool(preferences.wantsTracking),
                        "remindersEnabled": .bool(preferences.remindersEnabled),
                        "summaryEnabled": .bool(preferences.summaryEnabled),
                        "issueAlertsEnabled": .bool(preferences.issueAlertsEnabled),
                        "driftThresholdMeters": .int(Int64(preferences.driftThresholdMeters)),
                    ])], totalCount: 1)
                },
            ),
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "data-issues",
                    title: "Data issues",
                    summary: "Counts of data-quality issues by category for a year (cached scan).",
                    rowSchema: .object(["category": .string(), "count": .integer()]),
                    filters: .object(["year": .integer("Gregorian year")], required: ["year"]),
                    supportsSubscription: false,
                ),
                fetch: { query in
                    let year = try Self.year(query.filters)
                    let report = try await services.reports.yearReport(for: year)
                    let issues = try await services.resolution.issues(
                        year: year,
                        primaryRegions: Region.primaryRegions(in: report.totals),
                        driftThresholdMeters: Double(preferences.driftThresholdMeters),
                        force: false,
                    )
                    let counts = Self.issueCounts(issues)
                    let rows = counts.sorted { $0.key < $1.key }.map { category, count in
                        PortholeValue.object(["category": .string(category), "count": count])
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
        ]
    }

    // MARK: - Helpers

    private static func year(_ filters: PortholeValue) throws -> Int {
        guard let year = filters["year"]?.intValue else {
            throw PortholeError.invalidParameters("`year` is required")
        }
        return Int(year)
    }

    private static func issueCounts(_ issues: [any DataIssue]) -> [String: PortholeValue] {
        var counts: [String: Int] = [:]
        for category in DataIssueCategory.allCases {
            counts[String(describing: category)] = 0
        }
        for issue in issues {
            counts[String(describing: issue.category), default: 0] += 1
        }
        return counts.mapValues { .int(Int64($0)) }
    }

    private static func sampleRow(_ sample: LocationSample) -> PortholeValue {
        .object([
            "timestamp": .date(sample.timestamp),
            "latitude": .double(sample.coordinate.latitude),
            "longitude": .double(sample.coordinate.longitude),
            "horizontalAccuracy": .double(sample.horizontalAccuracy),
            "source": .string(String(describing: sample.source)),
        ])
    }
}
