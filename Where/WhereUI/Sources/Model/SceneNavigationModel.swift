import Observation
import RegionKit
import SwiftUI
import WhereCore

/// Session-scoped presentation state. Resizing changes containers, never this owner or its
/// children.
@MainActor @Observable
final class SceneNavigationModel {
    typealias TabID = MainTabSelection.TabID
    private var tabSelection = MainTabSelection()
    var selectedTab: TabID {
        get { tabSelection.selected }
        set { tabSelection.selected = newValue }
    }

    func reconcile(hasElsewhere: Bool) {
        tabSelection.reconcile(hasElsewhere: hasElsewhere)
    }

    let locations = Locations()
    let year = Year()
    let settings = Settings()

    init(selectedTab: TabID = .locations) {
        self.selectedTab = selectedTab
    }

    @MainActor @Observable
    final class Locations {
        enum Destination: Hashable {
            case elsewhere
            case flight(GPSCorrectionReview)
        }

        var selectedRegion: Region?
        var compactColumn = NavigationSplitViewColumn.sidebar
        var browsePath = NavigationPath()
        var detailPath = NavigationPath()
        var scrollPosition = ScrollPosition(idType: Region.self)
        var visibleRegion: Region?
        let history = HistoryNavigationModel()
        var calendar: CalendarNavigationModel {
            history.calendar
        }

        var showingResolution = false
        var planningDestination: PlannedStaysDestination? {
            get { history.planning.destination }
            set { history.planning.destination = newValue }
        }

        func select(region: Region) {
            guard selectedRegion != region || compactColumn != .detail else { return }
            if selectedRegion != region { detailPath = NavigationPath() }
            selectedRegion = region
            compactColumn = .detail
        }

        func open(_ destination: Destination) {
            browsePath.append(destination)
            compactColumn = .sidebar
        }

        func restoreBrowsePosition() {
            guard let visibleRegion else { return }
            scrollPosition.scrollTo(id: visibleRegion, anchor: .top)
        }
    }

    @MainActor @Observable
    final class Year {
        var mode: YearMode
        let history = HistoryNavigationModel()
        var calendar: CalendarNavigationModel {
            history.calendar
        }

        init(mode: YearMode = .calendar) {
            self.mode = mode
        }
    }

    @MainActor @Observable
    final class Settings {
        // Settings, evidence, and feature-gallery routes share the same stack.
        // NavigationPath retains each value's concrete Hashable identity.
        var path = NavigationPath()
        private var route: SettingsRoute?
        var compactColumn = NavigationSplitViewColumn.sidebar
        var selectedRoute: SettingsRoute? {
            get { route }
            set {
                guard route != newValue else { return }
                route = newValue
                path = NavigationPath()
                if newValue != nil { compactColumn = .detail }
            }
        }

        var searchText = ""
        var showRegions = false
    }
}
