import Foundation
@testable import InstallerKit
import Testing

struct UpdatePreferencesTests {
    @Test func roundTripsCache() throws {
        let value = UpdatePreferences(cached: .init(
            feedURL: UpdateFixtures.feedURL,
            checkedAt: UpdateFixtures.date,
            catalog: UpdateFixtures.catalog([
                2,
                1,
            ]),
        ))
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(UpdatePreferences.self, from: data) == value)
    }
}
