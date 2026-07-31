import SwiftUI

/// A stable identity shared by the phone tab bar and the iPad/Mac sidebar.
enum MainSection: Hashable, CaseIterable, Identifiable {
    case locations
    case year
    case settings

    var id: Self {
        self
    }

    var title: String {
        switch self {
            case .locations:
                String(localized: .tabLocations)
            case .year:
                String(localized: .tabYear)
            case .settings:
                String(localized: .tabSettings)
        }
    }

    var systemImage: String {
        switch self {
            case .locations:
                "location.fill"
            case .year:
                "calendar"
            case .settings:
                "gearshape.fill"
        }
    }
}
