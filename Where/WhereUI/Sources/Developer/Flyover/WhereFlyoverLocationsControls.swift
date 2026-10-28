#if DEBUG
    import SwiftUI

    /// Typed custom panel demonstrating state that changes the screen in place.
    struct WhereFlyoverLocationsControls: View {
        @Bindable var state: WhereFlyoverLocationsState

        var body: some View {
            Toggle("Show Resolve toolbar item", isOn: $state.showsResolve)
        }
    }

    #Preview {
        WhereFlyoverLocationsControls(
            state: WhereFlyoverLocationsState(
                report: PreviewSupport.loadedYearReportModel(),
            ),
        )
        .padding()
    }
#endif
