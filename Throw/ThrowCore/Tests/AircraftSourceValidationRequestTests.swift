import Foundation
import Testing
@testable import ThrowCore

struct AircraftSourceValidationRequestTests {
    @Test func credentialFreeDraftsHaveNoCredentialReplacement() throws {
        let readsb = try ReadsbConfiguration(
            aircraftJSONURL: #require(URL(string: "http://receiver.local/aircraft.json")),
        )
        let drafts: [AircraftSourceValidationDraft] = [
            .adsbLol,
            .readsb(readsb),
        ]

        for draft in drafts {
            #expect(draft.credentialReplacement == nil)
        }
    }

    @Test func paidDraftsDeriveTheirFixedCredentialIdentities() throws {
        let rapidAPICredential = try AircraftCredential(secret: "rapid-api-secret")
        let flightradar24Credential = try AircraftCredential(secret: "flightradar-secret")
        let rapidAPIDraft = AircraftSourceValidationDraft.adsbExchangeRapidAPI(
            ADSBExchangeConfiguration(pollingInterval: .defaultValue),
            replacementCredential: rapidAPICredential,
        )
        let flightradar24Draft = AircraftSourceValidationDraft.flightradar24(
            Flightradar24Configuration(pollingInterval: .defaultValue),
            replacementCredential: flightradar24Credential,
        )

        #expect(rapidAPIDraft.credentialReplacement?.id == .rapidAPI)
        #expect(rapidAPIDraft.credentialReplacement?.credential == rapidAPICredential)
        #expect(flightradar24Draft.credentialReplacement?.id == .flightradar24)
        #expect(flightradar24Draft.credentialReplacement?.credential == flightradar24Credential)
    }

    @Test func configurationDraftDoesNotStageACredentialReplacement() {
        let configuration = AircraftSourceConfiguration.flightradar24(
            Flightradar24Configuration(pollingInterval: .defaultValue),
        )

        let draft = AircraftSourceValidationDraft(configuration: configuration)

        #expect(draft.configuration == configuration)
        #expect(draft.credentialReplacement == nil)
    }
}
