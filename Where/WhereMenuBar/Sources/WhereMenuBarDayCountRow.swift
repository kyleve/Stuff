import SwiftUI
import WhereSurface

struct WhereMenuBarDayCountRow: View {
    let dayCount: WhereSurfaceSnapshot.DayCount

    var body: some View {
        HStack {
            WhereMenuBarRegionRow(region: dayCount.region)
            Spacer()
            Text(dayCount.days, format: .number)
                .monospacedDigit()
            Text(dayCount.days == 1 ? .menuBarDay : .menuBarDays)
                .foregroundStyle(.secondary)
        }
    }
}
