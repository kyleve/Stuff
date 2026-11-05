import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
enum RecordingPlaceTestSupport {
    static let coordinate = Coordinate(latitude: 40.71, longitude: -74)

    static func editor(_ fixture: RecordingReviewTestSupport.Fixture) throws
        -> RecordingPlaceEditorModel
    {
        let model = RecordingPlaceEditorModel(
            services: fixture.services,
            intent: .new(at: RecordingReviewTestSupport.date(0)),
        )
        guard case let .definition(definition) = model.draft
        else { throw RecordingReviewTestSupport.TestFailure.expectedPreview }
        definition.coordinate = coordinate
        return model
    }

    static func model(_ fixture: RecordingReviewTestSupport.Fixture) -> RecordingPlaceModel {
        .init(services: fixture.services, now: { RecordingReviewTestSupport.date(600) })
    }

    static func save(_ fixture: RecordingReviewTestSupport.Fixture) async throws
        -> RecordingPlaceDecision
    {
        let editor = try editor(fixture)
        await editor.review()
        await editor.apply()
        return try #require(await fixture.controls().places.first)
    }
}
