import Foundation
import SnapshotKitTesting
import Testing

@MainActor
@Suite(.serialized)
struct InstallerSiteSnapshotTests {
    @Test func site() async throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(
            forResource: "InstallerSiteSnapshots",
            withExtension: "json",
        ))
        let pages = try JSONDecoder().decode([Page].self, from: Data(contentsOf: url))
        #expect(Set(pages.map(\.name)) == Set(Page.Name.allCases))
        #expect(pages.count == Page.Name.allCases.count)
        let configurations: [SnapshotConfiguration] = [
            .init(layoutTraits: .phonePortrait, device: .iPhoneFullContent),
            .init(colorScheme: .dark, layoutTraits: .phonePortrait, device: .iPhoneFullContent),
            .init(layoutTraits: .tabletPortrait, device: .iPadFullContent),
            .init(colorScheme: .dark, layoutTraits: .tabletPortrait, device: .iPadFullContent),
        ]
        for page in pages {
            try await assertHTMLSnapshots(
                of: page.html,
                named: page.name.rawValue,
                configurations: configurations,
            )
        }
    }

    private struct Page: Decodable {
        enum Name: String, CaseIterable, Decodable {
            case index = "Index"
            case app = "App"
            case channel = "Channel"
            case retired = "Retired"
            case empty = "Empty"
            case unavailableHistory = "UnavailableHistory"
            case missingDetails = "MissingDetails"
            case preparing = "Preparing"
            case preparingApp = "PreparingApp"
            case failed = "Failed"
            case rebuilding = "Rebuilding"
            case unpublished = "Unpublished"
        }

        let name: Name
        let html: String
    }

    private final class BundleMarker: NSObject {}
}
