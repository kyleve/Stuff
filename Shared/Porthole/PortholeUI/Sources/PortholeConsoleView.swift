import SwiftUI

struct PortholeConsoleView: View {
    @Bindable var model: PortholeConsoleModel
    let controller: PortholePresentationController
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        List {
            Section("JavaScript") {
                TextEditor(text: $model.source).font(stylesheet.code.font)
                    .frame(minHeight: stylesheet.code.minimumHeight)
                    .portholeCodeInput()
                    .accessibilityLabel("JavaScript source")
                Text(
                    "Call a capability ID with { arguments, receiver }. Receiver is optional. Native mutations pause for review.",
                )
                .font(.caption).foregroundStyle(.secondary)
                Button("Run") { model.run(using: controller) }.disabled(model.isRunning)
                if model.isRunning { Button("Cancel", role: .cancel) { model.cancel() } }
            }
            Section("State") {
                switch model.state {
                    case .idle: Text("Ready")
                    case .running: ProgressView("Running or waiting for approval…")
                    case let .finished(value): PortholeValueView(value: value)
                    case let .failed(message): Text(message)
                    case .cancelled: Text(
                            "Cancellation requested. Native work may already have changed state.",
                        )
                }
            }
            Section("Execution evidence") {
                ForEach(model.entries) { entry in
                    VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                        Text(entry.label).font(.headline)
                        if let value = entry.value { PortholeValueView(value: value) }
                    }
                }
            }
        }
        .navigationTitle("Console")
    }
}
