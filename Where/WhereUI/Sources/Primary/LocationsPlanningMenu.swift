import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Compact Locations-toolbar access to the single planned stay.
struct LocationsPlanningMenu: View {
    let primaryRegions: [Region]
    var plannedStay: PlannedStay?
    let isClearing: Bool
    let editAction: (Region) -> Void
    let clearAction: () -> Void

    var body: some View {
        if isClearing {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: .locationForecastClearingStay))
        } else {
            Menu {
                if let plannedStay {
                    Section(String(localized: .locationsPlanningCurrentSection)) {
                        Button {
                            editAction(plannedStay.region)
                        } label: {
                            Label(
                                WhereFormat.locationsPlanningEdit(region: plannedStay.region),
                                systemSymbol: .checkmark,
                            )
                        }

                        Button(role: .destructive, action: clearAction) {
                            Label(
                                String(localized: .locationForecastRemovePlan),
                                systemSymbol: .trash,
                            )
                        }
                    }
                }

                let assignableRegions = primaryRegions.filter { $0 != plannedStay?.region }
                if !assignableRegions.isEmpty {
                    Section(String(localized: .locationsPlanningAssignSection)) {
                        ForEach(assignableRegions, id: \.self) { region in
                            Button(WhereFormat.locationsPlanningAssign(region: region)) {
                                editAction(region)
                            }
                        }
                    }
                }
            } label: {
                Label(
                    String(localized: .locationsPlanningMenu),
                    systemSymbol: .calendarBadgeClock,
                )
            }
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("where_planning_menu")
        }
    }

    private var accessibilityValue: String {
        guard let plannedStay else {
            return String(localized: .locationsPlanningNoCurrentValue)
        }
        return WhereFormat.locationsPlanningCurrentValue(region: plannedStay.region)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        LocationsPlanningMenu(
                            primaryRegions: [.california, .newYork],
                            plannedStay: PlannedStay(
                                region: .newYork,
                                through: CalendarDay(year: 2026, month: 8, day: 15),
                            ),
                            isClearing: false,
                            editAction: { _ in },
                            clearAction: {},
                        )
                    }
                }
        }
        .whereBroadwayRoot()
    }
#endif
