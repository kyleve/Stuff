import Foundation
import Observation
import WhereCore

/// Draft setup intent. Replacement is an explicit removal choice, never identity or consent
/// transfer. Discovery is advisory and cannot change an already edited recording toggle.
@MainActor
@Observable
final class OnboardingDeviceSetupModel {
    enum Discovery {
        case idle
        case loading
        case ready(RecordingOnboardingRecommendation)
        case failed(any Error)
    }

    enum Mode: Equatable {
        case additional
        case replacement(RecordingDeviceID, removeOldDevice: Bool)
    }

    private(set) var discovery = Discovery.idle
    private(set) var mode = Mode.additional
    var isConfirmingRemoval = false

    var isLoading: Bool {
        switch discovery {
            case .idle, .loading: true
            case .ready, .failed: false
        }
    }

    var existingDevices: [RecordingDevice] {
        guard case let .ready(recommendation) = discovery else { return [] }
        return recommendation.existingDevices
    }

    var replacementDeviceID: RecordingDeviceID? {
        get {
            guard case let .replacement(deviceID, _) = mode else { return nil }
            return deviceID
        }
        set {
            guard newValue != replacementDeviceID else { return }
            isConfirmingRemoval = false
            mode = newValue.map { .replacement($0, removeOldDevice: false) } ?? .additional
        }
    }

    var removesOldDevice: Bool {
        get {
            guard case let .replacement(_, removeOldDevice) = mode else { return false }
            return removeOldDevice
        }
        set {
            guard case let .replacement(deviceID, oldValue) = mode,
                  oldValue != newValue else { return }
            isConfirmingRemoval = false
            mode = .replacement(deviceID, removeOldDevice: newValue)
        }
    }

    var deviceToRemove: RecordingDeviceID? {
        removesOldDevice ? replacementDeviceID : nil
    }

    var replacementDevice: RecordingDevice? {
        existingDevices.first { $0.id == replacementDeviceID }
    }

    func discover(using model: WhereModel, context: InstallationRecordingContext) async {
        switch discovery {
            case .loading, .ready: return
            case .idle, .failed: break
        }
        discovery = .loading
        do {
            discovery = try await .ready(model.discoverRecordingRecommendation(for: context))
        } catch {
            discovery = .failed(error)
        }
    }
}
