import SwiftUI

struct HomeWidgetTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview {
        HomeWidgetTitle(title: WhereFormat.widgetYearTitle(year: PreviewSupport.year))
            .whereBroadwayRoot()
    }
#endif
