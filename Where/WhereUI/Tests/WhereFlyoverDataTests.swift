#if DEBUG
    import Flyover
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
    }
#endif
