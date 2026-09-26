import Flagger
@testable import FlaggerUI
import Testing

@MainActor
struct FlaggerModelTests {
    @Test
    func observesAnExternalUpdateImmediatelyAfterInitialization() async throws {
        let fixture = try await makeFlaggerModelFixture()
        let flag = UIFlags().enabled

        try await fixture.flagger.set(true, for: flag)
        try await waitUntil { fixture.model.ui.enabled }

        #expect(fixture.model.ui.enabled)
    }

    @Test
    func filtersBySourceGroupNameIDAndDescription() async throws {
        let model = try await makeFlaggerModel()

        model.searchText = "renderer"
        #expect(model.filteredFlags.map(\.id) == [UIFlags().enabled.id])
        model.searchText = "UI Tests"
        #expect(model.filteredFlags.count == 2)
        model.searchText = "missing"
        #expect(model.filteredFlags.isEmpty)
    }
}
