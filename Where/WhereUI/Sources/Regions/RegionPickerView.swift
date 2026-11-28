import RegionKit
import SnapshotKit
import SwiftUI

/// Mounts a fresh picker model for each visit while the caller retains the edit draft.
struct RegionPickerView: View {
    private let makeModel: () -> RegionPickerModel

    init(draft: PrimaryRegionDraft, usedThisYear: Set<Region> = []) {
        self.init { RegionPickerModel(draft: draft, usedThisYear: usedThisYear) }
    }

    private init(makeModel: @escaping () -> RegionPickerModel) {
        self.makeModel = makeModel
    }

    var body: some View {
        ObservableHostingView(makeModel) {
            RegionPickerContent(model: $0)
        }
    }
}

#if DEBUG
    extension RegionPickerView: SnapshotProviding {
        private static func selectedSnapshotModel(search: String = "") -> RegionPickerModel {
            let draft = PrimaryRegionDraft()
            draft.toggle(.california)
            draft.toggle(.ontario)
            let model = RegionPickerModel(draft: draft)
            model.searchText = search
            return model
        }

        private struct SearchSnapshot: View {
            var body: some View {
                NavigationStack {
                    RegionPickerView { selectedSnapshotModel(search: "ON") }
                        .navigationTitle(String(localized: .settingsRegionsManage))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }

        static var snapshots: [SnapshotCase] {
            // The system search toolbar needs an attached scene to render its glass.
            var phone = SnapshotConfiguration.Frame.iPhoneFullContent
            phone.scenePolicy = .retained
            return [
                whereSnapshot(
                    name: "AvailableRegions",
                    configurations: [
                        .init(device: phone),
                        .init(dynamicType: .accessibility5, device: phone),
                    ],
                ) {
                    NavigationStack {
                        RegionPickerView { selectedSnapshotModel() }
                    }
                },
                whereSnapshot(
                    name: "Search",
                    configurations: [.init(device: phone)],
                    // The native clear button finishes appearing after the toolbar mounts.
                    settle: .settledAtLeast(minDuration: 1.0),
                ) {
                    SearchSnapshot()
                },
            ]
        }
    }
#endif

#if DEBUG
    #Preview { RegionPickerView.snapshotPreviews }

    #Preview("Empty") { RegionPickerEmptyPreview() }

    private struct RegionPickerEmptyPreview: View {
        var body: some View {
            NavigationStack {
                RegionPickerView(draft: PrimaryRegionDraft())
                    .navigationTitle(String(localized: .onboardingRegionsTitle))
            }
            .whereBroadwayRoot()
        }
    }
#endif

#if DEBUG
    extension RegionPickerView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(RegionPickerView.self) { id, world in
            .init(
                id: id,
                title: "Region Picker",
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "list",
                        title: "List",
                        world: world,
                    ) {
                        RegionPickerView(draft: PreviewSupport.primaryRegionDraft())
                    },
                ],
            )
        }
    }
#endif
