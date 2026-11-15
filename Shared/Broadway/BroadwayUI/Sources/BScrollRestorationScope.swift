import SwiftUI

private struct BScrollRestorationScope: ViewModifier {
    @State private var store = BScrollRestorationStore()

    func body(content: Content) -> some View {
        content.environment(\.bScrollRestorationStore, store)
    }
}

extension View {
    /// Own a restoration store above content that can be replaced during layout changes.
    public func bScrollRestorationScope() -> some View {
        modifier(BScrollRestorationScope())
    }

    /// Share a caller-owned store across replacement hosts within the same scene/session.
    public func bScrollRestorationScope(_ store: BScrollRestorationStore) -> some View {
        environment(\.bScrollRestorationStore, store)
    }
}
