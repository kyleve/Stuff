import SwiftUI
import Testing
import WhereTesting
@testable import WhereUI

@MainActor
struct DeveloperTabBarInsetTests {
    @Test func reduceKeepsTheLargestReportedInset() {
        var value = DeveloperTabBarInsetKey.defaultValue
        DeveloperTabBarInsetKey.reduce(value: &value) { 40 }
        #expect(value == 40)
        DeveloperTabBarInsetKey.reduce(value: &value) { 10 }
        #expect(value == 40)
        DeveloperTabBarInsetKey.reduce(value: &value) { 55 }
        #expect(value == 55)
    }

    /// The reporter must measure the *floating tab bar*, not just the home
    /// indicator: a tab's content bottom inset minus the window's own bottom inset
    /// is positive. Guards the assumption the developer overlay's clearance rests
    /// on — if a future SDK stops folding the tab bar into the content safe area,
    /// this catches it.
    @Test func reporterMeasuresFloatingTabBarHeight() throws {
        let box = InsetBox()
        let root = TabView {
            Tab("One", systemImage: "1.circle") {
                Color.clear.reportingDeveloperTabBarInset()
            }
            Tab("Two", systemImage: "2.circle") {
                Color.clear
            }
        }
        .onPreferenceChange(DeveloperTabBarInsetKey.self) { box.value = $0 }

        try show(UIHostingController(rootView: root)) { _ in
            try waitFor { box.value > 0 }
            #expect(box.value > 0)
        }
    }
}

/// Bridges the `@Sendable` `onPreferenceChange` callback back to the test. Reads
/// and writes are confined to the main actor by the hosted run loop.
private final class InsetBox: @unchecked Sendable {
    var value: CGFloat = 0
}
