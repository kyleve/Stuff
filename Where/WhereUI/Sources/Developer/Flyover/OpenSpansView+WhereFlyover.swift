#if DEBUG
    import PeriscopeCore
    import PeriscopeTools

    extension OpenSpansView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            OpenSpansView.self,
            title: "Open Spans",
        ) { _ in
            OpenSpansView(system: .shared)
        }
    }
#endif
