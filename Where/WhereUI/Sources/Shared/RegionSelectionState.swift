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
/// regions first, then any **non-tracked regions this day already uses**, then
/// **everything else** (collapsed). Membership in those groups is stable while
/// the form is open — it keys off the *initial* selection and the tracked set
/// (loaded once via ``applyTracked(_:)``), so toggling a row never makes it jump
/// sections. Until the tracked set loads, ``trackedRegions`` is `nil` and callers
/// fall back to the flat ``items`` list.
@Observable
final class RegionSelectionState {
    var items: [RegionToggleItem]

    /// The regions selected when the form opened, so the "already on this day"
    /// group stays fixed as the user toggles.
    private let initiallySelected: Set<Region>

    /// The user's tracked regions, loaded asynchronously by the form. `nil`
    /// until loaded — callers render the flat `items` list meanwhile.
    private(set) var trackedRegions: Set<Region>?

    /// Tracked regions in pick order, for the tracked group's row order.
    private var trackedOrder: [Region] = []

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
        initiallySelected = selectedRegions
    }

    var selectedRegions: Set<Region> {
        Set(items.filter(\.isOn).map(\.region))
    }

    /// Record the user's tracked/primary regions (in pick order) so the form can
    /// group the toggles. Idempotent-friendly: the form loads once.
    func applyTracked(_ primaryRegions: [PrimaryRegion]) {
        trackedOrder = primaryRegions.map(\.region)
        trackedRegions = Set(trackedOrder)
    }

    /// The tracked regions' rows, in pick order. Empty until ``applyTracked(_:)``.
    var trackedItems: [RegionToggleItem] {
        guard trackedRegions != nil else { return [] }
        let byRegion = Dictionary(
            items.map { ($0.region, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        return trackedOrder.compactMap { byRegion[$0] }
    }

    /// Rows for regions this day already uses but the user doesn't track — the
    /// initial selection minus the tracked set. Empty until loaded.
    var usedItems: [RegionToggleItem] {
        guard let tracked = trackedRegions else { return [] }
        return items
            .filter { initiallySelected.contains($0.region) && !tracked.contains($0.region) }
    }

    /// Every remaining row — neither tracked nor already on this day. Falls back
    /// to the full list until the tracked set loads.
    var otherItems: [RegionToggleItem] {
        guard let tracked = trackedRegions else { return items }
        return items
            .filter { !tracked.contains($0.region) && !initiallySelected.contains($0.region) }
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
