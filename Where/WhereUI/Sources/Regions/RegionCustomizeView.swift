import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Steps through each picked region in pick order, editing its look with
/// ``RegionAppearanceEditor``. Back/Next (Done on the last region) live in the
/// navigation bar, so the caller must place this inside a `NavigationStack`.
/// `onFinish` fires when the user advances past the last region; `onBack` fires
/// when they go back before the first (so onboarding returns to the picker and
/// the Settings editor returns to its pick phase).
struct RegionCustomizeView: View {
    @Bindable var draft: PrimaryRegionDraft
    var onBack: () -> Void = {}
    var onFinish: () -> Void = {}

    @State private var index = 0

    @Environment(\.stylesheet) private var stylesheet

    private var regions: [Region] {
        draft.selectedRegions
    }

    var body: some View {
        Group {
            if let region = currentRegion {
                RegionAppearanceEditor(region: region, appearance: $draft[appearanceFor: region])
                    .id(region)
                    .transition(.opacity)
            } else {
                // No selection to customize — nothing to step through.
                ContentUnavailableView(
                    String(localized: .regionPickerTitle),
                    systemSymbol: .map,
                    description: Text(String(localized: .regionPickerSubtitle)),
                )
            }
        }
        .animation(stylesheet.motion.captionFade, value: index)
        .navigationTitle(currentRegion?.localizedName ?? String(localized: .regionCustomizeTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: .onboardingBack), action: goBack)
            }
            ToolbarItem(placement: .principal) {
                RegionStepLabel(current: effectiveIndex + 1, total: regions.count)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(
                    isLast ? String(localized: .commonDone) : String(localized: .onboardingNext),
                    action: goNext,
                )
            }
        }
    }

    /// `index` clamped into range, so a stale/out-of-range value can never
    /// strand the user — the empty state (`currentRegion == nil`) is reserved for
    /// a genuinely empty selection, which the current flow never reaches.
    private var effectiveIndex: Int {
        guard !regions.isEmpty else { return 0 }
        return min(max(index, 0), regions.count - 1)
    }

    private var currentRegion: Region? {
        regions.isEmpty ? nil : regions[effectiveIndex]
    }

    private var isLast: Bool {
        effectiveIndex >= regions.count - 1
    }

    private func goBack() {
        if effectiveIndex == 0 {
            onBack()
        } else {
            index = effectiveIndex - 1
        }
    }

    private func goNext() {
        if isLast {
            onFinish()
        } else {
            index = effectiveIndex + 1
        }
    }
}

private struct RegionStepLabel: View {
    let current: Int
    let total: Int

    var body: some View {
        Text(WhereFormat.regionCustomizeStep(
            current: current,
            total: total,
        ))
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

#if DEBUG
    extension RegionCustomizeView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Editor",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    RegionCustomizeView(draft: PreviewSupport.primaryRegionDraft())
                }
            }

            whereSnapshot(
                name: "NeutralEditor",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    RegionCustomizeView(draft: neutralPreviewDraft())
                }
            }
        }

        private static func neutralPreviewDraft() -> PrimaryRegionDraft {
            let draft = PreviewSupport.primaryRegionDraft()
            draft[appearanceFor: .california].color = .slate
            return draft
        }
    }

    #Preview("Stepping") {
        RegionCustomizeView.snapshotPreviews
    }
#endif

#if DEBUG
    extension RegionCustomizeView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            RegionCustomizeView.self,
            title: "Customize Regions",
        ) { _ in
            RegionCustomizeView(
                draft: PreviewSupport.primaryRegionDraft(),
            )
        }
    }
#endif
