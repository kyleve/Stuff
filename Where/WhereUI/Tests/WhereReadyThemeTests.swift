import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct WhereReadyThemeTests {
    @Test func previewChangesOnlyTheReadySubtreeAndClearRestoresTheSavedTheme() throws {
        let preview = try WhereThemePreviewModel.bundled()
        let launch = ProbeState()
        let ready = ProbeState()
        let host = UIHostingController(rootView: VStack {
            Probe(state: launch)
            Probe(state: ready).modifier(WhereReadyTheme())
        }.whereThemePreview(preview).whereBroadwayRoot(theme: .standard))
        try show(host) { _ in
            try waitFor { launch.documentID == .standard && ready.documentID == .standard }
            preview.select(.halloween)
            try waitFor { ready.documentID == .halloween }
            #expect(launch.documentID == .standard)
            #expect(ready.radius == 26)
            preview.clear()
            try waitFor { ready.documentID == .standard }
            #expect(launch.documentID == .standard)
            #expect(ready.radius == launch.radius)
        }
    }

    private final class ProbeState {
        var documentID: WhereThemeDocument.ID?
        var radius: CGFloat?
    }

    private struct Probe: View {
        let state: ProbeState
        @Environment(\.whereThemeDocument) private var document
        @Environment(\.stylesheet) private var stylesheet
        var body: some View {
            Color.clear.frame(width: 20, height: 20)
                .onChange(of: document?.validated, initial: true) { _, value in
                    state.documentID = value?.resolved.id
                }
                .onChange(of: stylesheet.card.regular.cornerRadius, initial: true) { _, value in
                    state.radius = value
                }
        }
    }
}
