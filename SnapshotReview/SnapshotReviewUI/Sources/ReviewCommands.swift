import SwiftUI

public struct ReviewCommands: Commands {
    private let model: ReviewBrowserModel
    public init(model: ReviewBrowserModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Snapshot Folder…") { model.isImporting = true }.keyboardShortcut("o")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model.undoManager?.undo() }.keyboardShortcut("z")
                .disabled(model.isBusy || model.undoManager?.canUndo != true)
            Button("Redo") { model.undoManager?.redo() }.keyboardShortcut(
                "z",
                modifiers: [.command, .shift],
            )
            .disabled(model.isBusy || model.undoManager?.canRedo != true)
        }
        CommandMenu("Snapshots") {
            Group {
                Button("Light") { model.appearance = .light }.keyboardShortcut("1")
                Button("Dark") { model.appearance = .dark }.keyboardShortcut("2")
                Button("Other") { model.appearance = .other }.keyboardShortcut("3")
                Button("Previous Other Configuration") { model.cycleOther(-1) }.keyboardShortcut(
                    .leftArrow,
                    modifiers: [.command, .option],
                )
                Button("Next Other Configuration") { model.cycleOther(1) }.keyboardShortcut(
                    .rightArrow,
                    modifiers: [.command, .option],
                )
                Divider()
                Button("Start Review") { model.startReview() }.keyboardShortcut(
                    "r",
                    modifiers: [.command, .shift],
                )
                Button("Review and Next") { Task { await model.reviewAndNext() } }.keyboardShortcut(
                    .return,
                    modifiers: .command,
                ).disabled(!model.canReviewDisplayedImage)
                Button("Skip") { model.advance(1) }.keyboardShortcut(
                    .rightArrow,
                    modifiers: .command,
                )
                Button("Back") { model.advance(-1) }.keyboardShortcut(
                    .leftArrow,
                    modifiers: .command,
                )
                Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r")
            }.disabled(model.isBusy)
        }
    }
}
