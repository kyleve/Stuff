import SwiftUI

struct OnboardingStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        switch model.step {
            case .welcome:
                WelcomeStepView()
            case .location:
                LocationStepView(model: model)
            case .source:
                SourceStepView(model: model)
            case .projection:
                ProjectionModeStepView(model: model)
            case .calibration:
                CalibrationStepView(model: model)
            case .appearance:
                AppearanceStepView(model: model)
            case .ready:
                ReadyStepView(model: model)
        }
    }
}
