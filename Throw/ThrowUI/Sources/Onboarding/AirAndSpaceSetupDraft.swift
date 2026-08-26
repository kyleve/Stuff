import ThrowCore

/// Reusable Air & Space configuration draft for onboarding and future View setup.
struct AirAndSpaceSetupDraft {
    var sourceChoice: AircraftSourceChoice?
    var readsbURL = "http://readsb.local/tar1090/data/aircraft.json"
    var rapidAPIKey = ""
    var pollingIntervalSeconds = Double(PollingInterval.defaultValue.seconds)
    var sourceValidation: SourceValidationState = .untested
    var validatedSource: ValidatedAircraftSourceDraft?
    var selectedMode: ProjectionMode?
    var mapRadius = MapViewport.defaultValue.radius.value
    var minimumElevation = SkyViewport.defaultValue.minimumElevation.degrees
}
