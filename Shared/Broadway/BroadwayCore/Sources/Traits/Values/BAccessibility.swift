//
//  BAccessibility.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/29/26.
//

import Foundation
import UIKit

extension BTraits {
    public var accessibility: BAccessibility {
        get { self[BAccessibility.self] }
        set { self[BAccessibility.self] = newValue }
    }
}

extension BTraits.Overrides {
    public var accessibility: BAccessibility? {
        get { self[BAccessibility.self] }
        set { self[BAccessibility.self] = newValue }
    }
}

/// A snapshot of the device's current accessibility settings.
///
/// Each property mirrors a corresponding `UIAccessibility` class property.
/// Use ``current()`` to read the live system state, or construct
/// instances directly for testing and previews.
public struct BAccessibility: Equatable, Hashable, Sendable {
    // MARK: Assistive Technologies

    public var isVoiceOverRunning: Bool
    public var isSwitchControlRunning: Bool
    public var isAssistiveTouchRunning: Bool
    public var isGuidedAccessEnabled: Bool

    // MARK: Vision

    public var isBoldTextEnabled: Bool
    public var isGrayscaleEnabled: Bool
    public var isInvertColorsEnabled: Bool
    public var isDarkerSystemColorsEnabled: Bool
    public var isReduceTransparencyEnabled: Bool
    public var shouldDifferentiateWithoutColor: Bool
    public var isOnOffSwitchLabelsEnabled: Bool
    public var buttonShapesEnabled: Bool

    // MARK: Motion

    public var isReduceMotionEnabled: Bool
    public var prefersCrossFadeTransitions: Bool
    public var isVideoAutoplayEnabled: Bool

    // MARK: Audio & Speech

    public var isMonoAudioEnabled: Bool
    public var isClosedCaptioningEnabled: Bool
    public var isSpeakScreenEnabled: Bool
    public var isSpeakSelectionEnabled: Bool

    // MARK: Other

    public var isShakeToUndoEnabled: Bool

    // MARK: Initialization

    public init(
        buttonShapesEnabled: Bool = false,
        isAssistiveTouchRunning: Bool = false,
        isBoldTextEnabled: Bool = false,
        isClosedCaptioningEnabled: Bool = false,
        isDarkerSystemColorsEnabled: Bool = false,
        isGrayscaleEnabled: Bool = false,
        isGuidedAccessEnabled: Bool = false,
        isInvertColorsEnabled: Bool = false,
        isMonoAudioEnabled: Bool = false,
        isOnOffSwitchLabelsEnabled: Bool = false,
        isReduceMotionEnabled: Bool = false,
        isReduceTransparencyEnabled: Bool = false,
        isShakeToUndoEnabled: Bool = false,
        isSpeakScreenEnabled: Bool = false,
        isSpeakSelectionEnabled: Bool = false,
        isSwitchControlRunning: Bool = false,
        isVideoAutoplayEnabled: Bool = false,
        isVoiceOverRunning: Bool = false,
        prefersCrossFadeTransitions: Bool = false,
        shouldDifferentiateWithoutColor: Bool = false,
    ) {
        self.buttonShapesEnabled = buttonShapesEnabled
        self.isAssistiveTouchRunning = isAssistiveTouchRunning
        self.isBoldTextEnabled = isBoldTextEnabled
        self.isClosedCaptioningEnabled = isClosedCaptioningEnabled
        self.isDarkerSystemColorsEnabled = isDarkerSystemColorsEnabled
        self.isGrayscaleEnabled = isGrayscaleEnabled
        self.isGuidedAccessEnabled = isGuidedAccessEnabled
        self.isInvertColorsEnabled = isInvertColorsEnabled
        self.isMonoAudioEnabled = isMonoAudioEnabled
        self.isOnOffSwitchLabelsEnabled = isOnOffSwitchLabelsEnabled
        self.isReduceMotionEnabled = isReduceMotionEnabled
        self.isReduceTransparencyEnabled = isReduceTransparencyEnabled
        self.isShakeToUndoEnabled = isShakeToUndoEnabled
        self.isSpeakScreenEnabled = isSpeakScreenEnabled
        self.isSpeakSelectionEnabled = isSpeakSelectionEnabled
        self.isSwitchControlRunning = isSwitchControlRunning
        self.isVideoAutoplayEnabled = isVideoAutoplayEnabled
        self.isVoiceOverRunning = isVoiceOverRunning
        self.prefersCrossFadeTransitions = prefersCrossFadeTransitions
        self.shouldDifferentiateWithoutColor = shouldDifferentiateWithoutColor
    }

    public init(with provider: SettingsProvider) {
        buttonShapesEnabled = provider.buttonShapesEnabled
        isAssistiveTouchRunning = provider.isAssistiveTouchRunning
        isBoldTextEnabled = provider.isBoldTextEnabled
        isClosedCaptioningEnabled = provider.isClosedCaptioningEnabled
        isDarkerSystemColorsEnabled = provider.isDarkerSystemColorsEnabled
        isGrayscaleEnabled = provider.isGrayscaleEnabled
        isGuidedAccessEnabled = provider.isGuidedAccessEnabled
        isInvertColorsEnabled = provider.isInvertColorsEnabled
        isMonoAudioEnabled = provider.isMonoAudioEnabled
        isOnOffSwitchLabelsEnabled = provider.isOnOffSwitchLabelsEnabled
        isReduceMotionEnabled = provider.isReduceMotionEnabled
        isReduceTransparencyEnabled = provider.isReduceTransparencyEnabled
        isShakeToUndoEnabled = provider.isShakeToUndoEnabled
        isSpeakScreenEnabled = provider.isSpeakScreenEnabled
        isSpeakSelectionEnabled = provider.isSpeakSelectionEnabled
        isSwitchControlRunning = provider.isSwitchControlRunning
        isVideoAutoplayEnabled = provider.isVideoAutoplayEnabled
        isVoiceOverRunning = provider.isVoiceOverRunning
        prefersCrossFadeTransitions = provider.prefersCrossFadeTransitions
        shouldDifferentiateWithoutColor = provider.shouldDifferentiateWithoutColor
    }
}

extension BAccessibility: BTraitsValue {
    public static var defaultValue: Self {
        .init()
    }

    @MainActor public static func currentValue(
        from _: UIViewController,
    ) -> BAccessibility {
        .current()
    }

    @MainActor public static func makeObserver(
        with _: UIViewController,
        onChange: @MainActor @escaping @Sendable (BAccessibility) -> Void,
    ) -> BAccessibility.Observer {
        .init { _, new in onChange(new) }
    }
}

extension BAccessibility {
    /// A provider which returns the current accessibility settings on the device.
    ///
    /// Instead of accessing `UIAccessibility.{...}` directly, utilize `BAccessibility.systemSettings`.
    public protocol SettingsProvider: AnyObject, Sendable {
        // MARK: Assistive Technologies

        var isVoiceOverRunning: Bool { get }
        var isSwitchControlRunning: Bool { get }
        var isAssistiveTouchRunning: Bool { get }
        var isGuidedAccessEnabled: Bool { get }

        // MARK: Vision

        var isBoldTextEnabled: Bool { get }
        var isGrayscaleEnabled: Bool { get }
        var isInvertColorsEnabled: Bool { get }
        var isDarkerSystemColorsEnabled: Bool { get }
        var isReduceTransparencyEnabled: Bool { get }
        var shouldDifferentiateWithoutColor: Bool { get }
        var isOnOffSwitchLabelsEnabled: Bool { get }
        var buttonShapesEnabled: Bool { get }

        // MARK: Motion

        var isReduceMotionEnabled: Bool { get }
        var prefersCrossFadeTransitions: Bool { get }
        var isVideoAutoplayEnabled: Bool { get }

        // MARK: Audio & Speech

        var isMonoAudioEnabled: Bool { get }
        var isClosedCaptioningEnabled: Bool { get }
        var isSpeakScreenEnabled: Bool { get }
        var isSpeakSelectionEnabled: Bool { get }

        // MARK: Other

        var isShakeToUndoEnabled: Bool { get }
    }
}

extension BAccessibility {
    /// Returns a snapshot of the current device accessibility settings
    /// by reading each `UIAccessibility` class property.
    public static func current(
        with provider: any SettingsProvider = BAccessibility.systemSettings,
    ) -> BAccessibility {
        BAccessibility(with: provider)
    }

    /// The provider which returns the current accessibility values from`UIAccessibility.{...}`.
    public static let systemSettings: any SettingsProvider = SystemSettingsProvider()
}

extension BAccessibility {
    /// Manages `NotificationCenter` registrations for system accessibility
    /// changes and reports diffs via a callback.
    /// Call ``start()`` and ``stop()`` to control the observation lifecycle.
    @MainActor
    public final class Observer: BTraitsValueObserver {
        private let onChange: @MainActor @Sendable (BAccessibility, BAccessibility) -> Void

        private let notificationCenter: NotificationCenter
        private let settingsProvider: SettingsProvider

        private var old: BAccessibility?

        private var isObserving: Bool = false

        init(
            notificationCenter: NotificationCenter = .default,
            settingsProvider: any SettingsProvider = BAccessibility.systemSettings,
            onChange: @MainActor @escaping @Sendable (BAccessibility, BAccessibility) -> Void,
        ) {
            self.notificationCenter = notificationCenter
            self.settingsProvider = settingsProvider
            self.onChange = onChange
            old = nil
        }

        /// Begins observing accessibility changes. Safe to call multiple times;
        /// subsequent calls while already observing are no-ops.
        public func start() {
            guard !isObserving else { return }

            isObserving = true
            old = .init(with: settingsProvider)

            for name in Self.notifications {
                notificationCenter.addObserver(
                    self,
                    selector: #selector(accessibilityDidChange(_:)),
                    name: name,
                    object: nil,
                )
            }
        }

        /// Stops observing accessibility changes and removes all notification
        /// registrations. Safe to call multiple times or before ``start()``.
        public func stop() {
            guard isObserving else { return }

            isObserving = false

            for name in Self.notifications {
                notificationCenter.removeObserver(self, name: name, object: nil)
            }

            old = nil
        }

        @objc private func accessibilityDidChange(_: Notification) {
            let new = BAccessibility(with: settingsProvider)

            guard let old, old != new else { return }

            self.old = new
            onChange(old, new)
        }

        static let notifications: [Notification.Name] = [
            UIAccessibility.assistiveTouchStatusDidChangeNotification,
            UIAccessibility.boldTextStatusDidChangeNotification,
            UIAccessibility.buttonShapesEnabledStatusDidChangeNotification,
            UIAccessibility.closedCaptioningStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            UIAccessibility.differentiateWithoutColorDidChangeNotification,
            UIAccessibility.grayscaleStatusDidChangeNotification,
            UIAccessibility.guidedAccessStatusDidChangeNotification,
            UIAccessibility.invertColorsStatusDidChangeNotification,
            UIAccessibility.monoAudioStatusDidChangeNotification,
            UIAccessibility.onOffSwitchLabelsDidChangeNotification,
            UIAccessibility.prefersCrossFadeTransitionsStatusDidChange,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.shakeToUndoDidChangeNotification,
            UIAccessibility.speakScreenStatusDidChangeNotification,
            UIAccessibility.speakSelectionStatusDidChangeNotification,
            UIAccessibility.switchControlStatusDidChangeNotification,
            UIAccessibility.videoAutoplayStatusDidChangeNotification,
            UIAccessibility.voiceOverStatusDidChangeNotification,
        ]
    }
}

extension BAccessibility {
    private final class SystemSettingsProvider: SettingsProvider, @unchecked Sendable {
        var isVoiceOverRunning: Bool {
            UIAccessibility.isVoiceOverRunning
        }

        var isSwitchControlRunning: Bool {
            UIAccessibility.isSwitchControlRunning
        }

        var isAssistiveTouchRunning: Bool {
            UIAccessibility.isAssistiveTouchRunning
        }

        var isGuidedAccessEnabled: Bool {
            UIAccessibility.isGuidedAccessEnabled
        }

        var isBoldTextEnabled: Bool {
            UIAccessibility.isBoldTextEnabled
        }

        var isGrayscaleEnabled: Bool {
            UIAccessibility.isGrayscaleEnabled
        }

        var isInvertColorsEnabled: Bool {
            UIAccessibility.isInvertColorsEnabled
        }

        var isDarkerSystemColorsEnabled: Bool {
            UIAccessibility.isDarkerSystemColorsEnabled
        }

        var isReduceTransparencyEnabled: Bool {
            UIAccessibility.isReduceTransparencyEnabled
        }

        var shouldDifferentiateWithoutColor: Bool {
            UIAccessibility.shouldDifferentiateWithoutColor
        }

        var isOnOffSwitchLabelsEnabled: Bool {
            UIAccessibility.isOnOffSwitchLabelsEnabled
        }

        var buttonShapesEnabled: Bool {
            UIAccessibility.buttonShapesEnabled
        }

        var isReduceMotionEnabled: Bool {
            UIAccessibility.isReduceMotionEnabled
        }

        var prefersCrossFadeTransitions: Bool {
            UIAccessibility.prefersCrossFadeTransitions
        }

        var isVideoAutoplayEnabled: Bool {
            UIAccessibility.isVideoAutoplayEnabled
        }

        var isMonoAudioEnabled: Bool {
            UIAccessibility.isMonoAudioEnabled
        }

        var isClosedCaptioningEnabled: Bool {
            UIAccessibility.isClosedCaptioningEnabled
        }

        var isSpeakScreenEnabled: Bool {
            UIAccessibility.isSpeakScreenEnabled
        }

        var isSpeakSelectionEnabled: Bool {
            UIAccessibility.isSpeakSelectionEnabled
        }

        var isShakeToUndoEnabled: Bool {
            UIAccessibility.isShakeToUndoEnabled
        }
    }
}
