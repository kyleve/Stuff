@testable import BroadwayCore
import Foundation
import Testing
import UIKit

struct BAccessibilityTests {
    // MARK: - Default Initialization

    @Test("Default init sets all properties to false")
    func defaultInit() {
        let a = BAccessibility()

        #expect(a.buttonShapesEnabled == false)
        #expect(a.isAssistiveTouchRunning == false)
        #expect(a.isBoldTextEnabled == false)
        #expect(a.isClosedCaptioningEnabled == false)
        #expect(a.isDarkerSystemColorsEnabled == false)
        #expect(a.isGrayscaleEnabled == false)
        #expect(a.isGuidedAccessEnabled == false)
        #expect(a.isInvertColorsEnabled == false)
        #expect(a.isMonoAudioEnabled == false)
        #expect(a.isOnOffSwitchLabelsEnabled == false)
        #expect(a.isReduceMotionEnabled == false)
        #expect(a.isReduceTransparencyEnabled == false)
        #expect(a.isShakeToUndoEnabled == false)
        #expect(a.isSpeakScreenEnabled == false)
        #expect(a.isSpeakSelectionEnabled == false)
        #expect(a.isSwitchControlRunning == false)
        #expect(a.isVideoAutoplayEnabled == false)
        #expect(a.isVoiceOverRunning == false)
        #expect(a.prefersCrossFadeTransitions == false)
        #expect(a.shouldDifferentiateWithoutColor == false)
    }

    // MARK: - Per-Property Initialization

    @Test("Each property can be set individually", arguments: [
        \BAccessibility.buttonShapesEnabled,
        \BAccessibility.isAssistiveTouchRunning,
        \BAccessibility.isBoldTextEnabled,
        \BAccessibility.isClosedCaptioningEnabled,
        \BAccessibility.isDarkerSystemColorsEnabled,
        \BAccessibility.isGrayscaleEnabled,
        \BAccessibility.isGuidedAccessEnabled,
        \BAccessibility.isInvertColorsEnabled,
        \BAccessibility.isMonoAudioEnabled,
        \BAccessibility.isOnOffSwitchLabelsEnabled,
        \BAccessibility.isReduceMotionEnabled,
        \BAccessibility.isReduceTransparencyEnabled,
        \BAccessibility.isShakeToUndoEnabled,
        \BAccessibility.isSpeakScreenEnabled,
        \BAccessibility.isSpeakSelectionEnabled,
        \BAccessibility.isSwitchControlRunning,
        \BAccessibility.isVideoAutoplayEnabled,
        \BAccessibility.isVoiceOverRunning,
        \BAccessibility.prefersCrossFadeTransitions,
        \BAccessibility.shouldDifferentiateWithoutColor,
    ])
    func settingIndividualProperty(keyPath: WritableKeyPath<BAccessibility, Bool>) {
        var a = BAccessibility()
        a[keyPath: keyPath] = true

        #expect(a[keyPath: keyPath] == true)
        #expect(a != BAccessibility())
    }

    // MARK: - Equatable

    @Test("Two default instances are equal")
    func defaultEquality() {
        #expect(BAccessibility() == BAccessibility())
    }

    @Test("Instances with different values are not equal")
    func inequality() {
        let a = BAccessibility()
        let b = BAccessibility(isVoiceOverRunning: true)
        #expect(a != b)
    }

    @Test("Instances with identical non-default values are equal")
    func equalWithNonDefaults() {
        let a = BAccessibility(isBoldTextEnabled: true, isReduceMotionEnabled: true)
        let b = BAccessibility(isBoldTextEnabled: true, isReduceMotionEnabled: true)
        #expect(a == b)
    }

    // MARK: - Hashable

    @Test("Equal instances have the same hash")
    func equalHash() {
        let a = BAccessibility(isReduceMotionEnabled: true, isVoiceOverRunning: true)
        let b = BAccessibility(isReduceMotionEnabled: true, isVoiceOverRunning: true)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Can be used as a Set element")
    func usableInSet() {
        let a = BAccessibility()
        let b = BAccessibility(isVoiceOverRunning: true)
        let set: Set<BAccessibility> = [a, b, a]
        #expect(set.count == 2)
    }

    // MARK: - Mutability

    @Test("Properties are mutable")
    func mutability() {
        var a = BAccessibility()
        a.isVoiceOverRunning = true
        a.isReduceMotionEnabled = true

        #expect(a.isVoiceOverRunning == true)
        #expect(a.isReduceMotionEnabled == true)

        a.isVoiceOverRunning = false
        #expect(a.isVoiceOverRunning == false)
    }
}

// MARK: - Mock SettingsProvider

private final class MockSettingsProvider: BAccessibility.SettingsProvider, @unchecked Sendable {
    var isVoiceOverRunning = false
    var isSwitchControlRunning = false
    var isAssistiveTouchRunning = false
    var isGuidedAccessEnabled = false
    var isBoldTextEnabled = false
    var isGrayscaleEnabled = false
    var isInvertColorsEnabled = false
    var isDarkerSystemColorsEnabled = false
    var isReduceTransparencyEnabled = false
    var shouldDifferentiateWithoutColor = false
    var isOnOffSwitchLabelsEnabled = false
    var buttonShapesEnabled = false
    var isReduceMotionEnabled = false
    var prefersCrossFadeTransitions = false
    var isVideoAutoplayEnabled = false
    var isMonoAudioEnabled = false
    var isClosedCaptioningEnabled = false
    var isSpeakScreenEnabled = false
    var isSpeakSelectionEnabled = false
    var isShakeToUndoEnabled = false
}

// MARK: - SettingsProvider Tests

struct BAccessibilitySettingsProviderTests {
    @Test("init(with:) reads all values from the provider")
    func initFromProvider() {
        let mock = MockSettingsProvider()
        mock.isVoiceOverRunning = true
        mock.isReduceMotionEnabled = true
        mock.buttonShapesEnabled = true

        let snapshot = BAccessibility(with: mock)

        #expect(snapshot.isVoiceOverRunning == true)
        #expect(snapshot.isReduceMotionEnabled == true)
        #expect(snapshot.buttonShapesEnabled == true)
        #expect(snapshot.isBoldTextEnabled == false)
    }

    @Test("current(with:) uses the provided settings")
    func currentWithProvider() {
        let mock = MockSettingsProvider()
        mock.isBoldTextEnabled = true

        let snapshot = BAccessibility.current(with: mock)

        #expect(snapshot.isBoldTextEnabled == true)
        #expect(snapshot.isVoiceOverRunning == false)
    }
}

// MARK: - Observer Tests

@MainActor struct BAccessibilityObserverTests {
    // MARK: - Lifecycle

    @Test("start and stop complete without error")
    func startStop() {
        let observer = BAccessibility.Observer { _, _ in }
        observer.start()
        observer.stop()
    }

    @Test("Calling start twice is safe")
    func doubleStart() {
        let observer = BAccessibility.Observer { _, _ in }
        observer.start()
        observer.start()
        observer.stop()
    }

    @Test("Calling stop without start is safe")
    func stopWithoutStart() {
        let observer = BAccessibility.Observer { _, _ in }
        observer.stop()
    }

    @Test("Calling stop twice is safe")
    func doubleStop() {
        let observer = BAccessibility.Observer { _, _ in }
        observer.start()
        observer.stop()
        observer.stop()
    }

    @Test("Can restart after stopping")
    func restart() {
        let observer = BAccessibility.Observer { _, _ in }
        observer.start()
        observer.stop()
        observer.start()
        observer.stop()
    }

    @Test("Deallocation after start does not crash")
    func deallocAfterStart() {
        var observer: BAccessibility.Observer? = .init { _, _ in }
        observer?.start()
        observer = nil
        _ = observer
    }

    // MARK: - Injected NotificationCenter

    @Test("Observer does not respond to notifications from the default center when injected")
    func isolatedFromDefault() {
        let center = NotificationCenter()
        var callCount = 0

        let observer = BAccessibility.Observer(notificationCenter: center) { _, _ in
            callCount += 1
        }
        observer.start()

        NotificationCenter.default.post(
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
        )

        #expect(callCount == 0)

        observer.stop()
    }

    @Test("Stop removes registrations from the injected center")
    func stopRemovesFromInjected() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var callCount = 0

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { _, _ in
            callCount += 1
        }
        observer.start()
        observer.stop()

        mock.isVoiceOverRunning = true
        center.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        #expect(callCount == 0)
    }

    // MARK: - Change Observation with Mock Provider

    @Test("Fires onChange when provider values change")
    func firesOnChange() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var callCount = 0

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { _, _ in
            callCount += 1
        }
        observer.start()

        mock.isVoiceOverRunning = true
        center.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        #expect(callCount == 1)

        observer.stop()
    }

    @Test("onChange delivers correct old and new snapshots")
    func deliversCorrectSnapshots() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var received: (old: BAccessibility, new: BAccessibility)?

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { old, new in
            received = (old, new)
        }
        observer.start()

        mock.isVoiceOverRunning = true
        center.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        #expect(received?.old.isVoiceOverRunning == false)
        #expect(received?.new.isVoiceOverRunning == true)

        observer.stop()
    }

    @Test("Does not fire onChange when provider values have not changed")
    func noSpuriousCallback() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var callCount = 0

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { _, _ in
            callCount += 1
        }
        observer.start()

        center.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        #expect(callCount == 0)

        observer.stop()
    }

    @Test("Sequential changes deliver sequential callbacks with updated values")
    func sequentialChanges() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var snapshots: [(old: BAccessibility, new: BAccessibility)] = []

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { old, new in
            snapshots.append((old, new))
        }
        observer.start()

        mock.isVoiceOverRunning = true
        center.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        mock.isReduceMotionEnabled = true
        center.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)

        #expect(snapshots.count == 2)

        #expect(snapshots[0].old.isVoiceOverRunning == false)
        #expect(snapshots[0].new.isVoiceOverRunning == true)

        #expect(snapshots[1].old.isReduceMotionEnabled == false)
        #expect(snapshots[1].new.isReduceMotionEnabled == true)
        #expect(snapshots[1].new.isVoiceOverRunning == true)

        observer.stop()
    }

    @Test("Does not fire onChange after stop even when provider changes")
    func noCallbackAfterStop() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var callCount = 0

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { _, _ in
            callCount += 1
        }
        observer.start()
        observer.stop()

        mock.isVoiceOverRunning = true
        center.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        #expect(callCount == 0)
    }

    @Test("Restarting observer picks up current provider state")
    func restartPicksUpCurrent() {
        let center = NotificationCenter()
        let mock = MockSettingsProvider()
        var received: (old: BAccessibility, new: BAccessibility)?

        let observer = BAccessibility.Observer(notificationCenter: center, settingsProvider: mock) { old, new in
            received = (old, new)
        }

        mock.isVoiceOverRunning = true
        observer.start()

        mock.isReduceMotionEnabled = true
        center.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)

        #expect(received?.old.isVoiceOverRunning == true)
        #expect(received?.old.isReduceMotionEnabled == false)
        #expect(received?.new.isReduceMotionEnabled == true)

        observer.stop()
    }
}
