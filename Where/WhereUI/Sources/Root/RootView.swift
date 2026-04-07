import SwiftUI

public struct RootView: View {
    @State private var viewModel: RootViewModel

    public init(viewModel: RootViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        TabView {
            DashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
                }

            HistoryView(viewModel: viewModel)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

            ManualEntryView()
                .tabItem {
                    Label("Manual", systemImage: "square.and.pencil")
                }
        }
        .task {
            if viewModel.snapshot == nil {
                await viewModel.load()
            }
        }
    }
}
