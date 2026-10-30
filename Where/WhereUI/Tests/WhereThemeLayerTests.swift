import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct WhereThemeLayerTests {
    @Test func hostActivityAndScenePhaseStopAndRestartLayerPlayback() throws {
        let theme = try activeThemeBackground()
        func content(isActive: Bool, scenePhase: ScenePhase) -> some View {
            Color.white
                .whereThemeOverlay(.locationsBackground)
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

    @Test func documentSlotsPreserveHostBounds() throws {
        let theme = try WhereThemeExamples.christmas.prepare()
        let host = Color.white.frame(width: 90, height: 60)
            .whereThemeBackground(.regularCardBackground, cornerRadius: 12)
            .whereThemeOverlay(.regularCardOverlay, cornerRadius: 12)
            .whereBroadwayRoot(themeDocument: theme)
        let image = try #require(ImageRenderer(content: host).uiImage)
        #expect(image.size == CGSize(width: 90, height: 60))
    }
}
