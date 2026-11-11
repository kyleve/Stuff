import SwiftUI

/// A native scroll binding retained by the nearest explicit restoration scope.
/// Use distinct roles for independent panes. Context changes discard the previous position.
@MainActor
@propertyWrapper
public struct BScrollPosition<ID: Hashable & Sendable>: @MainActor DynamicProperty {
    @Environment(\.bScrollRestorationStore) private var sharedStore
    @State private var localStore = BScrollRestorationStore()
    private let key: BScrollRestorationStore.Key
    private let context: () -> AnyHashable
    private var resolvedEntry: BScrollRestorationStore.Entry<ID>?

    public init(
        _ view: (some View).Type,
        role: some Hashable,
        context: some Hashable,
        idType: ID.Type,
    ) {
        key = .init(
            view: ObjectIdentifier(view),
            role: AnyHashable(role),
            content: ObjectIdentifier(idType),
        )
        self.context = { AnyHashable(context) }
    }

    /// Resolve a context supplied by an observable input when the owning view updates.
    public init(
        _ view: (some View).Type,
        role: some Hashable,
        context: @escaping @MainActor () -> some Hashable,
        idType: ID.Type,
    ) {
        key = .init(
            view: ObjectIdentifier(view),
            role: AnyHashable(role),
            content: ObjectIdentifier(idType),
        )
        self.context = { AnyHashable(context()) }
    }

    public mutating func update() {
        resolvedEntry = (sharedStore ?? localStore).entry(
            for: key,
            context: context(),
            idType: ID.self,
        )
    }

    private var entry: BScrollRestorationStore.Entry<ID> {
        guard let resolvedEntry else {
            preconditionFailure("BScrollPosition must be read from a mounted view")
        }
        return resolvedEntry
    }

    public var wrappedValue: ScrollPosition {
        get { entry.position }
        nonmutating set { entry.position = newValue }
    }

    public var projectedValue: Binding<ScrollPosition> {
        // Capture this render's entry. An obsolete task or outgoing view cannot
        // redirect a write into a new context's entry.
        let entry = entry
        // Register the value with SwiftUI even when the consumer only reads the binding.
        _ = entry.position
        return Binding(get: { entry.position }, set: { entry.position = $0 })
    }

    /// Apply the view's initial policy once its content is ready, once per context.
    /// Native layout can publish a provisional target before asynchronous data arrives.
    public func initialize(_ initialPosition: @autoclosure () -> ScrollPosition) {
        guard !entry.isInitialized else { return }
        entry.position = initialPosition()
        entry.isInitialized = true
    }
}
