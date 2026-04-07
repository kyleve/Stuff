import SwiftUI

public struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var manualEntryViewModel: ManualEntryViewModel

    public init(
        viewModel: RootViewModel,
        manualEntryViewModel: ManualEntryViewModel,
    ) {
        _viewModel = State(initialValue: viewModel)
        _manualEntryViewModel = State(initialValue: manualEntryViewModel)
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

            ManualEntryView(
                rootViewModel: viewModel,
                viewModel: manualEntryViewModel,
            )
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
