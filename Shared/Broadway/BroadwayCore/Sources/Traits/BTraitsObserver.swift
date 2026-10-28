//
//  BTraitsObserver.swift
//  BroadwayCore
//

import Foundation
import UIKit

/// Observes all trait types registered in a ``BTraits`` instance,
/// maintaining a live snapshot and notifying the caller when any
/// trait changes.
///
/// The observer reads its configuration (which types to observe)
/// from the ``BTraits`` value passed at init, reads the current
/// values from the view controller hierarchy, and creates
/// per-type observers via each type's ``BTraitsValue/makeObserver(onChange:)``.
@MainActor
public final class BTraitsObserver {
    // MARK: Public

    /// The current aggregated traits. Updated automatically when
    /// any observed trait value changes.
    public private(set) var traits: BTraits

    // MARK: Initialization

    /// - Parameter traits: The ``BTraits`` container whose registrations
    ///   determine which types are observed.
    /// - Parameter viewController: The view controller used to read
    ///   initial trait values via ``BTraitsValue/currentValue(from:)``.
    /// - Parameter onChange: Called with the updated ``BTraits``
    ///   whenever any observed trait value changes.
    public init(
        traits: BTraits,
        from viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (BTraits) -> Void,
    ) {
        self.traits = traits
        self.onChange = onChange

        self.traits.readCurrentValues(from: viewController)

        for reg in traits.registrations {
            let regID = reg.id

            let observer = reg.createObserver(viewController) { [weak self] newValue in
                guard let self else { return }

                let old = self.traits
                self.traits.setValue(newValue, for: regID)

                if self.traits != old {
                    onChange(self.traits)
                }
            }

            observers.append(observer)
        }
    }

    // MARK: Lifecycle

    /// Starts all registered trait observers. Safe to call multiple times.
    public func start() {
        guard !started else { return }
        started = true
        for observer in observers {
            observer.start()
        }
    }

    /// Stops all registered trait observers. Safe to call multiple times.
    public func stop() {
        guard started else { return }
        started = false
        for observer in observers {
            observer.stop()
        }
    }

    // MARK: Private

    private let onChange: @MainActor @Sendable (BTraits) -> Void
    private var observers: [any BTraitsValueObserver] = []
    private var started = false
}
