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
        for page in pages {
            try await assertHTMLSnapshots(
                of: page.html,
                named: page.name.rawValue,
                configurations: page.name.configurations,
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

            var configurations: [SnapshotConfiguration] {
                let phone = SnapshotConfiguration(
                    layoutTraits: .phonePortrait,
                    device: .iPhoneFullContent,
                )
                let phoneDark = SnapshotConfiguration(
                    colorScheme: .dark,
                    layoutTraits: .phonePortrait,
                    device: .iPhoneFullContent,
                )
                let tablet = SnapshotConfiguration(
                    layoutTraits: .tabletPortrait,
                    device: .iPadFullContent,
                )
                let tabletDark = SnapshotConfiguration(
                    colorScheme: .dark,
                    layoutTraits: .tabletPortrait,
                    device: .iPadFullContent,
                )
                // Main layouts own responsive/appearance coverage; status pages retain their unique
                // content.
                return switch self {
                    case .index, .app, .channel: [phone, phoneDark, tablet, tabletDark]
                    case .failed, .preparing: [phone, phoneDark]
                    case .rebuilding: [phone, tablet]
                    case .retired, .empty, .unavailableHistory, .missingDetails, .preparingApp,
                         .unpublished: [phone]
                }
            }
        }

        let name: Name
        let html: String
    }

    private final class BundleMarker: NSObject {}
}
