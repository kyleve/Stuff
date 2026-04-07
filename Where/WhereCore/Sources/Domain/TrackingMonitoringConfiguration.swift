import Foundation

public struct TrackingMonitoringConfiguration: Equatable, Sendable {
    public let jurisdictionRegions: [TaxJurisdiction]
    public let wantsSignificantLocationChanges: Bool
    public let wantsVisitMonitoring: Bool
    public let wakeNotificationHour: Int

    public init(
        jurisdictionRegions: [TaxJurisdiction] = [.california, .newYork],
        wantsSignificantLocationChanges: Bool = true,
        wantsVisitMonitoring: Bool = true,
        wakeNotificationHour: Int = 20,
    ) {
        self.jurisdictionRegions = jurisdictionRegions
        self.wantsSignificantLocationChanges = wantsSignificantLocationChanges
        self.wantsVisitMonitoring = wantsVisitMonitoring
        self.wakeNotificationHour = wakeNotificationHour
    }
}
