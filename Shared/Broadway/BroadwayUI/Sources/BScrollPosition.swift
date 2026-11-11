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
    @State private var mount = Mount()
    private var resolvedAttachment: Attachment?

    private struct Restoration {
        let position: ScrollPosition
        let anchor: UnitPoint?
    }

    private final class Attachment {
        let entry: BScrollRestorationStore.Entry<ID>
        var pending: Restoration?
        let userRevision: Int

        init(entry: BScrollRestorationStore.Entry<ID>) {
            self.entry = entry
            userRevision = entry.userRevision
            pending = Restoration(position: entry.position, anchor: entry.anchor)
        }
    }

    @MainActor
    private final class Mount {
        private var store: BScrollRestorationStore?
        private var context: AnyHashable?
        private var key: BScrollRestorationStore.Key?
        private var attachment: Attachment?

        func resolve(
            store: BScrollRestorationStore,
            key: BScrollRestorationStore.Key,
            context: AnyHashable,
        ) -> Attachment {
            if self.store === store, self.key == key, self.context == context,
               let attachment { return attachment }
            let attachment = Attachment(entry: store.entry(
                for: key,
                context: context,
                idType: ID.self,
            ))
            self.store = store
            self.key = key
            self.context = context
            self.attachment = attachment
            return attachment
        }
    }

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
        // An outgoing view can still render while its replacement is mounted.
        // Only a new mount, scope, or context may claim the store's current entry.
        resolvedAttachment = mount.resolve(
            store: sharedStore ?? localStore,
            key: key,
            context: context(),
        )
    }

    private var attachment: Attachment {
        guard let resolvedAttachment else {
            preconditionFailure("BScrollPosition must be read from a mounted view")
        }
        return resolvedAttachment
    }

    private var entry: BScrollRestorationStore.Entry<ID> {
        attachment.entry
    }

    /// Alignment used for semantic restoration; native user scrolling adopts top alignment.
    public var anchor: UnitPoint? {
        entry.anchor
    }

    public var wrappedValue: ScrollPosition {
        get { entry.position }
        nonmutating set { entry.position = newValue }
    }

    public var projectedValue: Binding<ScrollPosition> {
        // Preserve SwiftUI's observable binding transaction, and capture this entry
        // so an outgoing view cannot redirect a write into a replacement context.
        @Bindable var entry = entry
        return $entry.position
    }

    /// Restore once per mount when content is ready, or apply this context's initial policy.
    public func initialize(id: ID, anchor: UnitPoint) {
        initialize(position: ScrollPosition(id: id, anchor: anchor), anchor: anchor)
    }

    public func initialize(edge: Edge) {
        initialize(position: ScrollPosition(idType: ID.self, edge: edge), anchor: nil)
    }

    private func initialize(position: ScrollPosition, anchor: UnitPoint?) {
        let attachment = attachment
        guard let restoration = attachment.pending else { return }
        attachment.pending = nil
        guard attachment.userRevision == entry.userRevision else { return }
        // Mutate the live position so repeated semantic commands notify its native binding.
        if entry.isInitialized, let edge = restoration.position.edge {
            entry.position.scrollTo(edge: edge)
            entry.anchor = nil
        } else if entry.isInitialized,
                  let target = restoration.position.viewID(type: ID.self)
        {
            entry.position.scrollTo(id: target, anchor: restoration.anchor)
            entry.anchor = restoration.anchor
        } else {
            entry.position = position
            entry.anchor = anchor
        }
        entry.isInitialized = true
    }

    /// Use semantic commands to retain alignment, which native ScrollPosition does not expose.
    public func scrollTo(id: ID, anchor: UnitPoint) {
        attachment.pending = nil
        entry.isInitialized = true
        entry.anchor = anchor
        entry.position.scrollTo(id: id, anchor: anchor)
    }

    public func scrollTo(edge: Edge) {
        attachment.pending = nil
        entry.isInitialized = true
        entry.anchor = nil
        entry.position.scrollTo(edge: edge)
    }
}
