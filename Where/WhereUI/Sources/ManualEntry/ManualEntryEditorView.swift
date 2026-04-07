import SwiftUI
import WhereCore

struct ManualEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let initialDraft: ManualEntryDraft
    private let onSave: (ManualEntryDraft) -> Void

    @State private var timestamp: Date
    @State private var jurisdiction: TaxJurisdiction
    @State private var note: String
    @State private var kind: ManualLogEntry.Kind

    init(
        draft: ManualEntryDraft,
        onSave: @escaping (ManualEntryDraft) -> Void,
    ) {
        initialDraft = draft
        self.onSave = onSave
        _timestamp = State(initialValue: draft.timestamp)
        _jurisdiction = State(initialValue: draft.jurisdiction)
        _note = State(initialValue: draft.note)
        _kind = State(initialValue: draft.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    DatePicker(
                        "Date",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute],
                    )

                    Picker("Kind", selection: $kind) {
                        Text("Supplemental").tag(ManualLogEntry.Kind.supplemental)
                        Text("Correction").tag(ManualLogEntry.Kind.correction)
                    }
                    .pickerStyle(.segmented)

                    Picker("Jurisdiction", selection: $jurisdiction) {
                        ForEach(jurisdictionOptions, id: \.self) { option in
                            Text(option.displayName)
                                .tag(option)
                        }
                    }

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3 ... 6)
                }
            }
            .navigationTitle(initialDraft.id == nil ? "New Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            ManualEntryDraft(
                                id: initialDraft.id,
                                timestamp: timestamp,
                                jurisdiction: jurisdiction,
                                note: note,
                                kind: kind,
                            ),
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private var jurisdictionOptions: [TaxJurisdiction] {
        let preferredStates: [TaxJurisdiction] = [.california, .newYork, .unknown]
        let remainingStates = USState.allCases
            .map(TaxJurisdiction.state)
            .filter { !preferredStates.contains($0) }
            .sorted { $0.displayName < $1.displayName }

        return preferredStates + remainingStates
    }
}
