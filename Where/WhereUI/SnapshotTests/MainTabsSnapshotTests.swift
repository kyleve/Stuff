@_spi(Capture) import SnapshotKit
import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct MainTabsSnapshotTests {
    @Test func halloweenLocationsLightDark() async throws {
        try await assertThemeSnapshot(MainTabs.themeSnapshot(.halloween, selection: .locations))
    }

    @Test func halloweenOtherTabsLightDark() async throws {
        for selection: MainTabSelection.TabID in [.elsewhere, .year, .settings] {
            try await assertThemeSnapshot(MainTabs.themeSnapshot(.halloween, selection: selection))
        }
    }

    @Test func halloweenLocationsExtended() async throws {
        let snapshot = try await MainTabs.themeSnapshot(.halloween, selection: .locations)
        await assertThemeSnapshot(snapshot.withThemeConfigurations([
            .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
            .init(contrast: .increased, device: .iPhoneFullContent),
            .init(device: .iPhoneFullContent, snapshotType: .accessibility),
            .init(device: .iPadFullContent),
            .init(colorScheme: .dark, device: .iPadFullContent),
        ]))
    }

    @Test func halloweenOtherTabsExtended() async throws {
        for selection: MainTabSelection.TabID in [.elsewhere, .year, .settings] {
            let snapshot = try await MainTabs.themeSnapshot(.halloween, selection: selection)
            await assertThemeSnapshot(snapshot.withThemeConfigurations([
                .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                .init(device: .iPadFullContent),
            ]))
        }
    }

    @Test func holidayLocationsLightDark() async throws {
        try await assertThemeSnapshot(MainTabs.themeSnapshot(.holiday, selection: .locations))
    }

    @Test func holidayOtherTabsLightDark() async throws {
        for selection: MainTabSelection.TabID in [.elsewhere, .year, .settings] {
            try await assertThemeSnapshot(MainTabs.themeSnapshot(.holiday, selection: selection))
        }
    }

    @Test func holidayLocationsExtended() async throws {
        let snapshot = try await MainTabs.themeSnapshot(.holiday, selection: .locations)
        await assertThemeSnapshot(snapshot.withThemeConfigurations([
            .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
            .init(contrast: .increased, device: .iPhoneFullContent),
            .init(device: .iPhoneFullContent, snapshotType: .accessibility),
            .init(device: .iPadFullContent),
            .init(colorScheme: .dark, device: .iPadFullContent),
        ]))
    }

    @Test func holidayOtherTabsExtended() async throws {
        for selection: MainTabSelection.TabID in [.elsewhere, .year, .settings] {
            let snapshot = try await MainTabs.themeSnapshot(.holiday, selection: selection)
            await assertThemeSnapshot(snapshot.withThemeConfigurations([
                .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                .init(device: .iPadFullContent),
            ]))
        }
    }

    @Test func mainTabs() async {
        await assertSnapshots(of: MainTabs.self)
    }
}
