import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct SnapshotImageRenderingTests {
    @Test func aNilInsetOverrideKeepsTheNativeScene() async throws {
        try waitFor { hostKeyWindow() != nil }
        let window = try #require(hostKeyWindow())
        let scene = try #require(window.windowScene)
        let host = UIHostingController(rootView: Color.red)
        host.view.frame = window.bounds
        _ = try await renderSnapshotImage(
            of: host,
            named: "native-scene",
            safeAreaInsets: nil,
            settle: .immediate,
            onReadyToSnapshot: {
                #expect(window.windowScene === scene)
                #expect(hostKeyWindow() === window)
                #expect(host.view.window === window)
            },
        )
        #expect(host.parent == nil)
        #expect(hostKeyWindow() === window)
    }

    @Test(arguments: [false, true], [false, true])
    func restoresTheMarkedWindowAfterCapture(fails: Bool, anotherWindowIsKey: Bool) async throws {
        try waitFor { hostKeyWindow() != nil }
        let window = try #require(hostKeyWindow())
        let scene = try #require(window.windowScene)
        let otherWindow = UIWindow(windowScene: scene)
        defer {
            otherWindow.isHidden = true
            otherWindow.windowScene = nil
            window.makeKeyAndVisible()
        }
        if anotherWindowIsKey {
            otherWindow.rootViewController = UIViewController()
            otherWindow.makeKeyAndVisible()
            #expect(otherWindow.isKeyWindow)
            #expect(!window.isKeyWindow)
        }
        let root = try #require(window.rootViewController)
        let frame = window.frame
        let rootFrame = root.view.frame
        let rootInsets = root.additionalSafeAreaInsets
        let wasKey = window.isKeyWindow
        let wasHidden = window.isHidden
        let animationsWereEnabled = UIView.areAnimationsEnabled
        let host = UIHostingController(rootView: Color.red)
        let additionalInsets = UIEdgeInsets(top: 5, left: 7, bottom: 9, right: 11)
        host.additionalSafeAreaInsets = additionalInsets
        let contentFrame = CGRect(x: 0, y: 0, width: 280, height: 400)
        host.view.frame = contentFrame

        do {
            _ = try await renderSnapshotImage(
                of: host,
                named: "window-restoration",
                onReadyToMeasure: fails ? {} : nil,
                settle: .immediate,
                onReadyToSnapshot: {
                    #expect(window.windowScene == nil)
                    #expect(host.view.window === window)
                    #expect(window.bounds.size == contentFrame.size)
                },
            )
            #expect(!fails)
        } catch {
            #expect(fails)
            #expect(error as? SnapshotRenderingError == .measurementHookRequiresIntrinsicSizing(
                name: "window-restoration",
            ))
        }

        #expect(hostKeyWindow() === window)
        #expect(window.windowScene === scene)
        #expect(window.rootViewController === root)
        #expect(window.frame == frame)
        #expect(root.view.frame == rootFrame)
        #expect(root.additionalSafeAreaInsets == rootInsets)
        #expect(window.isKeyWindow == wasKey)
        if anotherWindowIsKey { #expect(otherWindow.isKeyWindow) }
        #expect(window.isHidden == wasHidden)
        #expect(UIView.areAnimationsEnabled == animationsWereEnabled)
        #expect(host.view.frame == contentFrame)
        #expect(host.additionalSafeAreaInsets == additionalInsets)
        #expect(host.parent == nil)
        #expect(root.children.isEmpty)
    }
}
