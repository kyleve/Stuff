import SwiftUI

#if canImport(UIKit)
    struct PortholeHostingSnapshotSurface: View {
        let fixture: PortholeHostingSnapshotFixture

        var body: some View {
            NavigationStack { PortholeHostingView(model: fixture.model) }
                .portholeBroadwayRoot()
                .environment(\.timeZone, .gmt)
                .task { await fixture.prepare() }
        }
    }
#endif
