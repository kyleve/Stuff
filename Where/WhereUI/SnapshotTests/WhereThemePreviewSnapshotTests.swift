import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct WhereThemePreviewSnapshotTests {
    @Test func seasonalDocumentsLightDark() async throws {
        try await capture(types: [.standard])
    }

    @Test func sharedSurfacesLightDark() async throws {
        for subject in WhereThemePreview.Subject.allCases where subject != .appearance {
            try await assertThemeSnapshot(WhereThemePreview.snapshot(subject, theme: .halloween))
        }
    }

    @Test func appearanceLightDark() async throws {
        try await assertThemeSnapshot(
            WhereThemePreview.snapshot(.appearance, theme: .halloween),
            testName: "sharedSurfacesLightDark()",
        )
    }

    @Test func seasonalDocumentsExtended() async throws {
        try await capture(types: [.accessibility])
    }

    @Test func sharedSurfacesExtended() async throws {
        for subject in WhereThemePreview.Subject.allCases where subject != .appearance {
            let snapshot = try WhereThemePreview.snapshot(subject, theme: .halloween)
            let configurations: [SnapshotConfiguration] = switch subject {
                case .forecast, .welcome, .privacy:
                    [
                        .init(dynamicType: .accessibility5),
                        .init(contrast: .increased),
                        .init(snapshotType: .accessibility),
                    ]
                case .timeline, .appearance, .planning:
                    [
                        .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                        .init(device: .iPhoneFullContent, snapshotType: .accessibility),
                    ]
            }
            await assertThemeSnapshot(snapshot.withThemeConfigurations(configurations))
        }
    }

    @Test func appearanceExtended() async throws {
        let snapshot = try WhereThemePreview.snapshot(.appearance, theme: .halloween)
        await assertThemeSnapshot(
            snapshot.withThemeConfigurations([
                .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                .init(device: .iPhoneFullContent, snapshotType: .accessibility),
            ]),
            testName: "sharedSurfacesExtended()",
        )
    }

    @Test func accessibilityPolicyExtended() async throws {
        for policy in WhereThemePreview.AccessibilityPolicy.allCases {
            try await assertThemeSnapshot(WhereThemePreview.snapshot(policy, theme: .halloween))
        }
    }

    @Test func holidaySharedSurfacesLightDark() async throws {
        for subject in WhereThemePreview.Subject.allCases {
            try await assertThemeSnapshot(WhereThemePreview.snapshot(subject, theme: .holiday))
        }
    }

    @Test func holidaySharedSurfacesExtended() async throws {
        for subject in WhereThemePreview.Subject.allCases {
            let snapshot = try WhereThemePreview.snapshot(subject, theme: .holiday)
            let configurations: [SnapshotConfiguration] = switch subject {
                case .forecast, .welcome, .privacy:
                    [
                        .init(dynamicType: .accessibility5),
                        .init(contrast: .increased),
                        .init(snapshotType: .accessibility),
                    ]
                case .timeline, .appearance, .planning:
                    [
                        .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                        .init(device: .iPhoneFullContent, snapshotType: .accessibility),
                    ]
            }
            await assertThemeSnapshot(snapshot.withThemeConfigurations(configurations))
        }
    }

    @Test func holidayAccessibilityPolicyExtended() async throws {
        for policy in WhereThemePreview.AccessibilityPolicy.allCases {
            try await assertThemeSnapshot(WhereThemePreview.snapshot(policy, theme: .holiday))
        }
    }

    private func capture(types: [SnapshotConfiguration.SnapshotType]) async throws {
        for example in WhereThemeExamples.allCases {
            let prepared = try example.prepare()
            await assertSnapshots(
                of: WhereThemePreview(theme: prepared),
                named: example.rawValue,
                configurations: SnapshotConfiguration.combinations(
                    devices: [.init(name: "iPhone", size: .intrinsic(maxWidth: 402))],
                    colorSchemes: [.light, .dark],
                    snapshotTypes: types,
                ),
                testName: "seasonalDocuments()",
            )
        }
    }
}
