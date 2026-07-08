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
@Observable
final class RegionSelectionState {
    var items: [RegionToggleItem]

    init(selectedRegions: Set<Region> = []) {
        items = Region.allCases.map {
            RegionToggleItem(region: $0, isOn: selectedRegions.contains($0))
        }
    }

    var selectedRegions: Set<Region> {
        Set(items.filter(\.isOn).map(\.region))
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
