#if DEBUG
    import SwiftUI
    import Testing
    @testable import WhereUI

    @MainActor
    struct CardDesignerEnvironmentTests {
        @Test func defaultsKeepTheDesignerAndOverrideAbsent() {
            let environment = EnvironmentValues()
            #expect(environment.cardDesignerModel == nil)
            #expect(environment.cardDesignerConfiguration == nil)
        }
    }
#endif
