import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct DeveloperTabBarInsetTests {
    @Test func windowReaderDiscardsTransientInsetsBeforeDeferredDelivery() async throws {
        let window = InsetsWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let view = DeveloperWindowInsetsReader.InsetView()
        var reported: [UIEdgeInsets] = []
        view.changed = { reported.append($0) }
        window.addSubview(view)
        let initial = try #require(view.pending)
        await initial.value
        #expect(reported == [.zero])

        window.simulatedInsets.bottom = 34
        view.scheduleUpdate()
        let pending = try #require(view.pending)
        // Restore the last published geometry before the task can execute.
        // The second request must invalidate the transient 34pt observation.
        window.simulatedInsets = .zero
        view.scheduleUpdate()
        await pending.value
        #expect(reported == [.zero])
        #expect(view.pending == nil)

        window.simulatedInsets.bottom = 20
        view.scheduleUpdate()
        let next = try #require(view.pending)
        await next.value
        #expect(reported == [.zero, UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)])
        #expect(view.pending == nil)
    }

    @Test(arguments: [false, true])
    func windowReaderDropsPendingDeliveryWhenRemoved(dismantles: Bool) async throws {
        let window = InsetsWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let view = DeveloperWindowInsetsReader.InsetView()
        var reported: [UIEdgeInsets] = []
        view.changed = { reported.append($0) }
        window.addSubview(view)
        let initial = try #require(view.pending)
        await initial.value
        #expect(reported == [.zero])

        window.simulatedInsets.bottom = 34
        view.scheduleUpdate()
        let pending = try #require(view.pending)
        if dismantles {
            DeveloperWindowInsetsReader.dismantleUIView(view, coordinator: ())
        } else {
            view.removeFromSuperview()
        }
        await pending.value
        #expect(reported == [.zero])
        #expect(view.pending == nil)
    }

    @Test func reduceKeepsEachEdgesLargestReportedInset() {
        var value = DeveloperTabBarInsetKey.defaultValue
        DeveloperTabBarInsetKey.reduce(value: &value) { EdgeInsets(
            top: 2,
            leading: 4,
            bottom: 40,
            trailing: 8,
        ) }
        DeveloperTabBarInsetKey.reduce(value: &value) { EdgeInsets(
            top: 1,
            leading: 12,
            bottom: 10,
            trailing: 6,
        ) }
        #expect(value == EdgeInsets(top: 2, leading: 12, bottom: 40, trailing: 8))
    }

    @Test func sideBarsUseTheAttachedWindowsPhysicalInsets() {
        let content = EdgeInsets(top: 8, leading: 64, bottom: 34, trailing: 84)
        let window = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        #expect(DeveloperBarInsets.additional(
            content: content,
            window: window,
            direction: .leftToRight,
        )
            == EdgeInsets(top: 8, leading: 64, bottom: 0, trailing: 0))
        #expect(DeveloperBarInsets.additional(
            content: EdgeInsets(top: 8, leading: 84, bottom: 34, trailing: 64),
            window: window,
            direction: .rightToLeft,
        ) == EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 64))
    }

    /// The reporter must measure the *floating tab bar*, not just the home
    /// indicator: a tab's content bottom inset minus the window's own bottom inset
    /// is positive. Guards the assumption the developer overlay's clearance rests
    /// on — if a future SDK stops folding the tab bar into the content safe area,
    /// this catches it.
    @Test func reporterMeasuresFloatingTabBarHeight() throws {
        let box = InsetBox()
        let root = TabView {
            Tab("One", systemSymbol: ._1Circle) {
                Color.clear.reportingDeveloperTabBarInset()
            }
            Tab("Two", systemSymbol: ._2Circle) {
                Color.clear
            }
        }
        .onPreferenceChange(DeveloperTabBarInsetKey.self) { box.value = $0 }

        try show(UIHostingController(rootView: root)) { _ in
            try waitFor { box.value.bottom > 0 }
            #expect(box.value.bottom > 0)
        }
    }
}

/// Supplies deterministic native-window changes without requiring a simulator scene.
@MainActor
private final class InsetsWindow: UIWindow {
    var simulatedInsets = UIEdgeInsets.zero

    override var safeAreaInsets: UIEdgeInsets {
        simulatedInsets
    }
}

/// Bridges the `@Sendable` `onPreferenceChange` callback back to the test. Reads
/// and writes are confined to the main actor by the hosted run loop.
private final class InsetBox: @unchecked Sendable {
    var value = EdgeInsets()
}
