import SFSafeSymbols
import SwiftUI

struct ReviewToolbar: ToolbarContent {
    let model: ReviewBrowserModel
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.isImporting = true } label: {
                Label("Open Folder", systemSymbol: .folder)
            }
            Button { Task { await model.refresh() } } label: { Label(
                "Refresh",
                systemSymbol: .arrowClockwise,
            ) }.disabled(model.root == nil)
            if model.isSingleImage {
                Button { model.select(model.selectedCase.map { .group($0) }) } label: { Label(
                    "Grid",
                    systemSymbol: .squareGrid2x2,
                ) }
            }
            Button { model.startReview() } label: { Label(
                "Start Review",
                systemSymbol: .checkmarkCircle,
            ) }.disabled(model.visibleImages.isEmpty)
            Menu {
                Button("Selected Case") { model.copyTodos(entireWorkspace: false) }
                    .disabled(model.selectedCase == nil)
                Button("Entire Workspace") { model.copyTodos(entireWorkspace: true) }
            } label: { Label("Copy Todos", systemSymbol: .docOnClipboard) }
                .disabled(model.root == nil)
        }
    }
}
