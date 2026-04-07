public protocol LocationWakeSource: Sendable {
    func startMonitoring(configuration: TrackingMonitoringConfiguration) async
    func refreshRegionMonitoring(configuration: TrackingMonitoringConfiguration) async
    func stopMonitoring() async
}
