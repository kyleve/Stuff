import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionExperiencePresentationTests {
    @Test func standardExperiencesHaveLocalizedDistinctPresentation() {
        let air = ProjectionExperiencePresentation(id: .airAndSpace)
        let transit = ProjectionExperiencePresentation(id: .transit)

        #expect(air.name == "Air & Space")
        #expect(transit.name == "Transit")
        #expect(air.description != transit.description)
        #expect(air.visibleContentLabel != transit.visibleContentLabel)
    }
}
