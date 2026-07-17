import Observation
import RegionKit
import WhereCore

/// One bindable toggle row in a region-selection form.
@Observable
final class RegionToggleItem: Identifiable {
    let region: Region
    var isOn: Bool

    var id: Region {
        region
    }

    init(region: Region, isOn: Bool) {
        self.region = region
        self.isOn = isOn
    }
}

/// Bindable region toggles for manual-day and relabel forms. Each region is an
/// `@Observable` row so `Toggle` can bind with `$item.isOn` instead of a
/// closure-based `Binding`.
///
/// The full catalog is a long list, so the forms group it: the user's **tracked**
/// regions first, then any **non-tracked regions used this year**, then
/// **everything else** (collapsed). Membership is stable while the form is open —
/// it keys off the tracked set + the year's used regions (loaded once via
/// ``applyGrouping(tracked:usedThisYear:)``), so toggling a row never makes it
/// jump sections. Until that loads, ``trackedRegions`` is `nil` and callers fall
/// back to the flat ``items`` list. `.other` (the catch-all) always stays in the
/// "everything else" group, never the used-this-year one.
@Observable
final class RegionSelectionState {
    var items: [RegionToggleItem]

    /// The user's tracked regions, loaded asynchronously by the form. `nil`
    /// until loaded — callers render the flat `items` list meanwhile.
    private(set) var trackedRegions: Set<Region>?

    /// Tracked regions in pick order, for the tracked group's row order.
    private var trackedOrder: [Region] = []

    /// Regions with days in the selected year (`.other` excluded), so a
    /// non-tracked place the user has been this year is easy to reach.
    private var usedThisYear: Set<Region> = []

    /// - Parameters:
    ///   - regions: the regions to offer as toggles, in order. Defaults to every
    ///     available catalog region plus the `.other` catch-all.
    ///   - selectedRegions: which of those start on.
    init(
        regions: [Region] = RegionCatalog.shared.all + [.other],
        selectedRegions: Set<Region> = [],
    ) {
        items = regions.map {
            RegionToggleItem(region: $0, isOn: selectedRegions.contains($0))
        }
    }

    var selectedRegions: Set<Region> {
        Set(items.filter(\.isOn).map(\.region))
    }

    /// Record the tracked/primary regions (pick order) and the regions used in
    /// the selected year so the form can group the toggles. The form loads once.
    func applyGrouping(tracked: [PrimaryRegion], usedThisYear: Set<Region>) {
        trackedOrder = tracked.map(\.region)
        trackedRegions = Set(trackedOrder)
        self.usedThisYear = usedThisYear
    }

    /// Whether the toggles are grouped yet (the tracked set has loaded). Until
    /// then callers render the flat ``items`` list.
    var isGrouped: Bool {
        trackedRegions != nil
    }

    /// The shared three-way grouping of the offered regions — tracked (as the
    /// stable reference set), used-this-year, everything else. Valid once
    /// ``isGrouped`` is true.
    var grouping: RegionGrouping {
        RegionGrouping(
            available: items.map(\.region),
            primary: trackedOrder,
            usedThisYear: usedThisYear,
        )
    }

    /// The toggle row for `region`, or `nil` if it isn't offered — so the grouped
    /// sections can bind their `Region`-keyed rows back to the live toggle state.
    func item(for region: Region) -> RegionToggleItem? {
        items.first { $0.region == region }
    }
}

/// Drives save-error alerts on manual-day forms. The message is the source of
/// truth; `isPresented` is a computed get/set for `.alert(isPresented:)`.
@Observable
final class SaveErrorAlertState {
    var message: String?

    var isPresented: Bool {
        get { message != nil }
        set { if !newValue { message = nil } }
    }
}
