#if DEBUG
    import SwiftUI
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverProvidingTests {
        @Test func derivesTheRegistrationIDFromTheConformingView() {
            #expect(FixtureView.flyoverID == WhereFlyoverScreenID(FixtureView.self))
            #expect(FixtureView.flyoverData.id == FixtureView.flyoverID)
        }

        private struct FixtureView: View, WhereFlyoverProviding {
            static let flyoverData = WhereFlyoverData(FixtureView.self) { _, _ in
                fatalError("The identity test does not build screen content.")
            }

            var body: some View {
                EmptyView()
            }
        }
    }
#endif
