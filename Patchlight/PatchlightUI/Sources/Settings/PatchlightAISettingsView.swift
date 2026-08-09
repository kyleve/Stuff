import PatchlightCore
import SwiftUI

enum PatchlightAIUserDefaults {
    static let globallyEnabled = "Patchlight.ai.globallyEnabled"
    static let provider = "Patchlight.ai.provider"
    static let preset = "Patchlight.ai.preset"
    static let advancedModelID = "Patchlight.ai.advancedModelID"

    static func provider(from rawValue: String) -> AIProvider {
        AIProvider(rawValue: rawValue) ?? .openAI
    }

    static func preset(from rawValue: String) -> AnalysisPreset {
        AnalysisPreset(rawValue: rawValue) ?? .balanced
    }
}

struct PatchlightAISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: PatchlightAppModel
    @AppStorage(PatchlightAIUserDefaults.globallyEnabled) private var globallyEnabled = false
    @AppStorage(PatchlightAIUserDefaults.provider) private var providerCode = AIProvider.openAI
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.preset) private var presetCode = AnalysisPreset.balanced
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.advancedModelID) private var advancedModelID = ""
    @State private var openAIKey = ""
    @State private var anthropicKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        String(localized: "enableAIAnalysis", defaultValue: "Enable AI Analysis"),
                        isOn: $globallyEnabled,
                    )
                    Picker(
                        String(localized: "analysisProvider", defaultValue: "Provider"),
                        selection: $providerCode,
                    ) {
                        Text("OpenAI").tag(AIProvider.openAI.rawValue)
                        Text("Anthropic").tag(AIProvider.anthropic.rawValue)
                    }
                    Picker(
                        String(localized: "analysisPreset", defaultValue: "Preset"),
                        selection: $presetCode,
                    ) {
                        Text(String(localized: "fast", defaultValue: "Fast"))
                            .tag(AnalysisPreset.fast.rawValue)
                        Text(String(localized: "balanced", defaultValue: "Balanced"))
                            .tag(AnalysisPreset.balanced.rawValue)
                        Text(String(localized: "deep", defaultValue: "Deep"))
                            .tag(AnalysisPreset.deep.rawValue)
                        Text(String(localized: "advanced", defaultValue: "Advanced"))
                            .tag(AnalysisPreset.advanced.rawValue)
                    }
                    if selectedPreset == .advanced {
                        TextField(
                            String(
                                localized: "explicitModelID",
                                defaultValue: "Explicit model ID",
                            ),
                            text: $advancedModelID,
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    Text(String(
                        localized: "aiPrivacySummary",
                        defaultValue: "Analysis is optional and runs only when you choose Run Analysis. Patchlight sends selected diffs and bounded exact-revision context directly to the selected provider, never to a Patchlight backend.",
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "analysis", defaultValue: "Analysis"))
                }

                providerKeySection(
                    provider: .openAI,
                    title: "OpenAI",
                    value: $openAIKey,
                )
                providerKeySection(
                    provider: .anthropic,
                    title: "Anthropic",
                    value: $anthropicKey,
                )

                if let settings = model.repositorySettings {
                    Section {
                        Toggle(
                            String(
                                localized: "enableForRepository",
                                defaultValue: "Enable for This Repository",
                            ),
                            isOn: Binding(
                                get: { settings.aiEnabled },
                                set: { enabled in
                                    Task {
                                        await model.setRepositoryAI(
                                            enabled: enabled,
                                            imageEnabled: enabled && settings.imageAIEnabled,
                                        )
                                    }
                                },
                            ),
                        )
                        Toggle(
                            String(
                                localized: "allowImageAnalysis",
                                defaultValue: "Allow Selected Snapshot Images",
                            ),
                            isOn: Binding(
                                get: { settings.imageAIEnabled },
                                set: { enabled in
                                    Task {
                                        await model.setRepositoryAI(
                                            enabled: settings.aiEnabled,
                                            imageEnabled: enabled,
                                        )
                                    }
                                },
                            ),
                        )
                        .disabled(!settings.aiEnabled)
                        Text(String(
                            localized: "imageAIConsentSummary",
                            defaultValue: "Image consent is separate and off by default. Only the base/head images currently selected in the snapshot workspace and local pixel metrics are sent.",
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } header: {
                        Text(String(
                            localized: "currentRepository",
                            defaultValue: "Current Repository",
                        ))
                    }
                }

                if let error = model.providerCredentialError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "aiSettings", defaultValue: "AI Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done", defaultValue: "Done")) { dismiss() }
                }
            }
            .task { await model.refreshProviderCredentialStatus() }
            .onChange(of: globallyEnabled) { _, enabled in
                if !enabled { model.cancelAIWork() }
            }
        }
    }

    private var selectedPreset: AnalysisPreset {
        PatchlightAIUserDefaults.preset(from: presetCode)
    }

    private func providerKeySection(
        provider: AIProvider,
        title: String,
        value: Binding<String>,
    ) -> some View {
        Section {
            SecureField(
                String(localized: "apiKey", defaultValue: "API key"),
                text: value,
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            HStack {
                if model.configuredProviders.contains(provider) {
                    Label(
                        String(localized: "keyStored", defaultValue: "Key Stored"),
                        systemImage: "checkmark.circle.fill",
                    )
                    .foregroundStyle(.green)
                } else {
                    Text(String(localized: "noKeyStored", defaultValue: "No key stored"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.configuredProviders.contains(provider) {
                    Button(
                        String(localized: "remove", defaultValue: "Remove"),
                        role: .destructive,
                    ) {
                        Task { await model.removeProviderCredential(provider) }
                    }
                }
                Button(String(localized: "save", defaultValue: "Save")) {
                    let key = value.wrappedValue
                    Task {
                        await model.saveProviderCredential(key, for: provider)
                        if model.providerCredentialError == nil { value.wrappedValue = "" }
                    }
                }
                .disabled(value.wrappedValue.trimmingCharacters(
                    in: .whitespacesAndNewlines,
                ).isEmpty)
            }
        } header: {
            Text(title)
        } footer: {
            Text(String(
                localized: "providerKeyStorageSummary",
                defaultValue: "Stored in this device's Keychain. Removing a provider key is independent of GitHub sign-out.",
            ))
        }
    }
}
