import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionPlaylistErrorPresentationTests {
    struct Example {
        let error: ProjectionPlaylistError
        let expectedDescription: String
    }

    @Test(arguments: [
        Example(
            error: .duplicateExperience,
            expectedDescription: "Each View can appear only once.",
        ),
        Example(
            error: .unknownExperience,
            expectedDescription: "Throw does not recognize this View. Select an available View.",
        ),
        Example(
            error: .unavailableExperience,
            expectedDescription: "This View is not available. Select an available View.",
        ),
        Example(
            error: .unconfiguredExperience,
            expectedDescription: "This View is not configured. Configure the View before you select it.",
        ),
        Example(
            error: .invalidSelection,
            expectedDescription: "Select one configured View.",
        ),
        Example(
            error: .invalidDwellDuration,
            expectedDescription: "Select a duration from 30 seconds to 30 minutes, in 30-second steps.",
        ),
    ])
    func playlistErrorsUseActionableDescriptions(_ example: Example) {
        #expect(example.error.localizedSettingsDescription == example.expectedDescription)
    }
}
