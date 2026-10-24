import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ThrowPostLaunchFailureTests {
    struct Example {
        let failure: ThrowPostLaunchFailure
        let owner: ThrowPostLaunchFailure.Owner
        let expectedMessage: String
    }

    @Test(arguments: [
        Example(
            failure: .preferencePersistence,
            owner: .preferencePersistence,
            expectedMessage: "Throw could not save these settings. The current session keeps your changes. Try again to save them for the next launch.",
        ),
        Example(
            failure: .aircraftSource,
            owner: .aircraftSource,
            expectedMessage: "Throw could not apply the aircraft source. The previous source remains active. Try again.",
        ),
        Example(
            failure: .rapidAPICredential,
            owner: .rapidAPICredential,
            expectedMessage: "Throw could not update the RapidAPI credential. Review the saved credential, then try again.",
        ),
        Example(
            failure: .flightradar24Credential,
            owner: .flightradar24Credential,
            expectedMessage: "Throw could not update the Flightradar24 credential. Review the saved credential, then try again.",
        ),
        Example(
            failure: .location(.gpsFixRequired),
            owner: .location,
            expectedMessage: "Refresh and accept a GPS fix before switching to GPS mode.",
        ),
        Example(
            failure: .location(.persistence),
            owner: .location,
            expectedMessage: "Throw could not save the observer location. The previous location remains active. Try again.",
        ),
        Example(
            failure: .playlist(.invalidDwellDuration),
            owner: .playlist,
            expectedMessage: "Select a duration from 30 seconds to 30 minutes, in 30-second steps.",
        ),
        Example(
            failure: .playlist(nil),
            owner: .playlist,
            expectedMessage: "Throw did not apply the View settings. Try again.",
        ),
        Example(
            failure: .onboarding,
            owner: .onboarding,
            expectedMessage: "Throw could not finish setup. Your choices remain on this screen. Try again.",
        ),
        Example(
            failure: .projectionPreparation,
            owner: .projectionPreparation,
            expectedMessage: "Throw could not prepare this View. Try again when the source updates.",
        ),
        Example(
            failure: .projectionRendering,
            owner: .projectionRendering,
            expectedMessage: "Throw could not update the projection. Try again.",
        ),
    ])
    func failuresUseOwnerSpecificRecoveryCopy(_ example: Example) {
        #expect(example.failure.owner == example.owner)
        #expect(String(localized: example.failure.userMessage) == example.expectedMessage)
    }
}
