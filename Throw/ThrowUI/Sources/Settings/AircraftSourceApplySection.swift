import SFSafeSymbols
import SwiftUI

struct AircraftSourceApplySection: View {
    @Bindable var model: AircraftSourceSettingsModel

    var body: some View {
        Section {
            Button(
                String(localized: actionTitle),
                systemSymbol: .checkmarkCircle,
                action: testAndApply,
            )
            .disabled(model.canTestAndApply == false)
            SourceValidationLabel(state: model.validation)
        } footer: {
            Text(.sourceApplyExplanation)
        }
    }

    private var actionTitle: LocalizedStringResource {
        if model.isCredentialSource, model.isEditingCredential {
            .sourceTestAndSaveCredential
        } else {
            .sourceTestAndApply
        }
    }

    private func testAndApply() {
        Task(name: "Throw test and apply aircraft source") {
            await model.testAndApply()
        }
    }
}
