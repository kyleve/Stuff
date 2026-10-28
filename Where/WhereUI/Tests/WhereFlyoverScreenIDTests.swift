#if DEBUG
    import Testing
    @testable import WhereUI

    struct WhereFlyoverScreenIDTests {
        @Test func derivesIdentityFromTheScreenType() {
            let first = WhereFlyoverScreenID(FirstScreen.self)
            let same = WhereFlyoverScreenID(FirstScreen.self)
            let second = WhereFlyoverScreenID(SecondScreen.self)
            let contextual = WhereFlyoverScreenID(FirstScreen.self, in: SecondScreen.self)

            #expect(first == same)
            #expect(first != second)
            #expect(first != contextual)
            #expect(Set([first, same, second, contextual]).count == 3)
            #expect(first.description.contains("FirstScreen"))
            #expect(contextual.description.contains("SecondScreen"))
            #expect(first.exportIdentifier == String(reflecting: FirstScreen.self))
            #expect(
                contextual.exportIdentifier
                    ==
                    "\(String(reflecting: FirstScreen.self)) in \(String(reflecting: SecondScreen.self))",
            )
        }

        private enum FirstScreen {}
        private enum SecondScreen {}
    }
#endif
