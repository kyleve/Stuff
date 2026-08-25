import Foundation

/// Stable output identities scoped to one controller window.
struct ControllerProjectionOutputs: Hashable {
    let preview: ProjectionOutputID
    let fullScreen: ProjectionOutputID
    let calibration: ProjectionOutputID
    #if DEBUG
        let projectorLab: ProjectionOutputID
    #endif

    init(namespace: UUID = UUID()) {
        let prefix = "controller-\(namespace.uuidString.lowercased())"
        preview = ProjectionOutputID(rawValue: "\(prefix)-preview")
        fullScreen = ProjectionOutputID(rawValue: "\(prefix)-full-screen")
        calibration = ProjectionOutputID(rawValue: "\(prefix)-calibration")
        #if DEBUG
            projectorLab = ProjectionOutputID(rawValue: "\(prefix)-projector-lab")
        #endif
    }
}
