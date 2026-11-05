import Flagger
import SwiftUI

struct FlaggerValueEditor: View {
    let flag: FlagSnapshot
    let model: FlaggerModel
    @State private var draft: String
    @State private var validationMessage: String?

    init(flag: FlagSnapshot, model: FlaggerModel) {
        self.flag = flag
        self.model = model
        _draft =
            State(initialValue: (try? (flag.storedValue ?? flag.effectiveValue).formatted) ??
                "null")
    }

    var body: some View {
        Form {
            Section("Value") {
                if case let .boolean(value) = editableValue {
                    Button(value ? "Disable" : "Enable", action: toggleBoolean)
                } else {
                    TextField("JSON value", text: $draft, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(5 ... 16)
                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                    Button("Apply JSON", action: applyJSON)
                }
                Button("Reset to Default", role: .destructive, action: reset)
                    .disabled(currentFlag.isDefault)
            }

            if currentFlag.isFrozen {
                Section {
                    Text("Changes apply the next time this flag’s lifetime begins.")
                }
            }

            if let failure = currentFlag.failure {
                Section("Invalid Override") {
                    Text(failure.message)
                        .foregroundStyle(.red)
                }
            }

            Section("Definition") {
                LabeledContent("ID", value: flag.id.rawValue)
                LabeledContent("Source", value: flag.source.name)
                LabeledContent("Group", value: flag.group.name)
                LabeledContent("Behavior", value: flag.behavior.label)
                LabeledContent("State", value: currentFlag.isFrozen ? "Frozen" : "Current")
                if let detail = flag.detail { Text(detail) }
            }
        }
        .navigationTitle(flag.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentFlag: FlagSnapshot {
        model.flags.first { $0.id == flag.id } ?? flag
    }

    private var editableValue: JSONValue {
        currentFlag.storedValue ?? currentFlag.effectiveValue
    }

    private func toggleBoolean() {
        guard case let .boolean(value) = editableValue else { return }
        Task { await model.setOverride(.boolean(value == false), for: flag.id) }
    }

    private func applyJSON() {
        do {
            let value = try JSONValue(formatted: draft)
            validationMessage = nil
            Task { await model.setOverride(value, for: flag.id) }
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func reset() {
        Task { await model.resetOverride(for: flag.id) }
    }
}
