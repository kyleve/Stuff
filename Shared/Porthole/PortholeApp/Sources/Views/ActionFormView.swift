import PortholeCore
import SwiftUI

/// A schema-generated form for invoking an action, showing the JSON result.
struct ActionFormView: View {
    @State var model: ActionFormModel

    var body: some View {
        Form {
            Section {
                Text(model.descriptor.summary).font(.callout)
                if model.descriptor.isDestructive {
                    Label(
                        "Destructive — changes app state.",
                        systemImage: "exclamationmark.triangle",
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Parameters") {
                if model.usesRawEditor {
                    TextEditor(text: $model.rawJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                } else if model.fields.isEmpty {
                    Text("No parameters").foregroundStyle(.secondary)
                } else {
                    ForEach($model.fields) { $field in
                        fieldRow($field)
                    }
                }
            }

            Section {
                Button {
                    Task { await model.run() }
                } label: {
                    if model.isRunning { ProgressView() } else { Text("Run") }
                }
                .disabled(model.isRunning)
            }

            if let error = model.errorMessage {
                Section("Error") {
                    Text(error).foregroundStyle(.red).font(.system(.body, design: .monospaced))
                }
            }
            if let result = model.resultText {
                Section("Result") {
                    Text(result).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(model.descriptor.title)
    }

    @ViewBuilder private func fieldRow(_ field: Binding<ActionFormModel.Field>) -> some View {
        switch field.wrappedValue.kind {
            case .boolean:
                Toggle(field.wrappedValue.id, isOn: field.boolValue)
            case .integer, .number:
                LabeledContent(field.wrappedValue.id) {
                    TextField("value", text: field.stringValue)
                        .multilineTextAlignment(.trailing)
                }
            case .string, .data, .date, .array, .object:
                LabeledContent(field.wrappedValue.id) {
                    TextField("value", text: field.stringValue)
                        .multilineTextAlignment(.trailing)
                }
        }
    }
}
