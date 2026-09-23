#if DEBUG
    import Flyover
    import SnapshotKit
    import SwiftUI
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverDataTests {
        @Test func derivesOutgoingTransitionsFromItsScreenIdentity() throws {
            let pushed = WhereFlyoverScreenID(Image.self)
            let presented = WhereFlyoverScreenID(Spacer.self)
            let data = WhereFlyoverData(
                Text.self,
                routes: [
                    .push(to: pushed),
                    .modal(to: presented),
                ],
            ) { _, _ in
                fatalError("The transition test does not build screen content.")
            }

            #expect(data.id == WhereFlyoverScreenID(Text.self))
            let transitions = data.transitions
            try #require(transitions.count == 2)
            #expect(transitions[0].source == data.id)
            #expect(transitions[0].destination == pushed)
            #expect(transitions[0].kind == .push)
            #expect(transitions[1].source == data.id)
            #expect(transitions[1].destination == presented)
            #expect(transitions[1].kind == .modal)
        }

        @Test func snapshotVariantsUseSnapshotNamesAsStableIdentifiers() {
            let data = WhereFlyoverData.snapshots(
                SnapshotScreen.self,
                title: "Snapshot",
            )

            let screen = data.screen(in: .preview())
            #expect(screen.variants.map(\.id.rawValue) == ["First", "Second"])
        }

        private struct SnapshotScreen: View, SnapshotProviding {
            var body: some View {
                EmptyView()
            }

            static var snapshots: [SnapshotCase] {
                [
                    SnapshotCase(name: "First", configurations: []) { EmptyView() },
                    SnapshotCase(name: "Second", configurations: []) { EmptyView() },
                ]
            }
        }
    }
#endif
