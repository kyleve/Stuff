public protocol JurisdictionResolving: Sendable {
    func jurisdiction(for event: TrackingWakeEvent) async -> TaxJurisdiction
}
