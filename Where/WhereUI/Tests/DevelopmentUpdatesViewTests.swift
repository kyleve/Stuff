#if DEBUG
    @_spi(Testing) import InstallerKitUI
    import Testing
    @testable import WhereUI

    @MainActor
    struct DevelopmentUpdatesViewTests {
        @Test func retainsEverySharedUpdaterScenarioInPreviewsAndFlyover() async throws {
            let expected = Set(InstallerPreview.Scenario.allCases.map(\.rawValue))
            let previewCases = DevelopmentUpdatesView.PreviewScenarios.snapshots
            let world = try await WhereFlyoverWorld.build()
            let screen = DevelopmentUpdatesView.flyoverData.screen(in: world)

            #expect(Set(previewCases.map(\.name)) == expected)
            #expect(previewCases.count == expected.count)
            #expect(Set(screen.variants.map(\.id.rawValue)) == expected)
            #expect(screen.variants.count == expected.count)
        }
    }
#endif
