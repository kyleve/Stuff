import CodeGraphModel
import SwiftUI

/// Controls which nodes and edges the canvas shows: scope toggles, per-kind and
/// per-module inclusion, name search, and the focus neighborhood.
struct FilterPanel: View {
    @Bindable var model: GraphViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Search names", text: $model.nameQuery)
                        .textFieldStyle(.roundedBorder)
                }
                Section("Scope") {
                    Toggle("First-party tests", isOn: $model.showTests)
                    Toggle("External symbols", isOn: $model.showExternal)
                    Toggle("Module nodes", isOn: $model.showModules)
                }
                if model.isFocused {
                    Section("Focus") {
                        LabeledContent("Centered on", value: model.focusName ?? "—")
                        Stepper("Depth: \(model.focusDepth)", value: $model.focusDepth, in: 1 ... 5)
                        Button("Clear focus", role: .destructive) { model.clearFocus() }
                    }
                }
                Section("Node kinds") {
                    ForEach(sortedNodeKinds, id: \.self) { kind in
                        toggleRow(
                            kind.rawValue,
                            color: GraphStyle.color(for: kind),
                            isOn: model.includedNodeKinds.contains(kind),
                        ) {
                            model.toggleNodeKind(kind)
                        }
                    }
                }
                Section("Edge kinds") {
                    ForEach(GraphViewModel.filterableEdgeKinds, id: \.self) { kind in
                        toggleRow(
                            kind.rawValue,
                            color: GraphStyle.color(for: kind),
                            isOn: model.includedEdgeKinds.contains(kind),
                        ) {
                            model.toggleEdgeKind(kind)
                        }
                    }
                }
                Section("Modules") {
                    ForEach(model.allModuleNames, id: \.self) { module in
                        toggleRow(
                            module,
                            color: .secondary,
                            isOn: !model.hiddenModules.contains(module),
                        ) {
                            model.toggleModuleHidden(module)
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") { model.resetFilters() }
                }
            }
        }
        .frame(minWidth: 340, minHeight: 520)
    }

    private func toggleRow(
        _ title: String,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sortedNodeKinds: [NodeKind] {
        GraphViewModel.filterableKinds.sorted { $0.rawValue < $1.rawValue }
    }
}
