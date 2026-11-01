import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct WhereComponentSurfaceTests {
    @Test func hostActivityAndScenePhaseStopAndRestartLayerPlayback() throws {
        let theme = try activeThemeBackground()
        func content(isActive: Bool, scenePhase: ScenePhase) -> some View {
            Color.clear
                .modifier(WhereComponentSurface(
                    role: .locations,
                    shape: Rectangle(),
                    finish: EmptyModifier(),
                ))
                .whereBroadwayRoot(themeDocument: theme)
                .environment(\.whereThemeLayersAreActive, isActive)
                .environment(\.scenePhase, scenePhase)
        }
        let host = UIHostingController(rootView: content(isActive: true, scenePhase: .active))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
            host.rootView = content(isActive: false, scenePhase: .active)
            try waitFor { !themeBackgroundIsRed(in: host.view) }
            host.rootView = content(isActive: true, scenePhase: .active)
            try waitFor { themeBackgroundIsRed(in: host.view) }
            host.rootView = content(isActive: true, scenePhase: .inactive)
            try waitFor { !themeBackgroundIsRed(in: host.view) }
        }
    }

    @Test func artworkPreservesHostBounds() throws {
        let theme = try LegacyThemeFixtures.prepare(.christmas)
        let host = Color.white.frame(width: 90, height: 60)
            .modifier(WhereComponentSurface(
                role: .regularCard,
                shape: RoundedRectangle(cornerRadius: 12),
                finish: EmptyModifier(),
            ))
            .whereBroadwayRoot(themeDocument: theme)
        let image = try #require(ImageRenderer(content: host).uiImage)
        #expect(image.size == CGSize(width: 90, height: 60))
    }
}
