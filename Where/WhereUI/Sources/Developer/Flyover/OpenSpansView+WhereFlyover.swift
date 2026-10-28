#if DEBUG
    import PeriscopeCore
    import PeriscopeTools

    extension OpenSpansView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            OpenSpansView.self,
            title: "Open Spans",
        ) { world in
            OpenSpansView(system: world.openSpansLogSystem)
        }
    }
#endif
