import BroadwayUI
import Observation
import SwiftUI
import TestHostSupport
import Testing

@MainActor
@Suite(.serialized)
struct BScrollPositionTests {
    @Test func nativeScrollViewRestoresItsVisibleTargetAfterReplacement() async throws {
        let fixture = NativeScrollFixture()
        fixture.initial = nil
        let host = UIHostingController(rootView: NativeScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try await show(host) { controller in
            try await waitForAsync { fixture.position != nil && fixture.visible.contains(0) }
            fixture.position?.wrappedValue.scrollTo(id: 12, anchor: .top)
            try await waitForAsync { fixture.visible.contains(12) && !fixture.visible.contains(0) }
            let before = fixture.position?.wrappedValue.viewID(type: Int.self)
            fixture.mounted = false
            try await waitForAsync { fixture.visible.isEmpty }
            fixture.mounted = true
            controller.view.layoutIfNeeded()
            try await waitForAsync { fixture.visible.contains(12) && !fixture.visible.contains(0) }
            #expect(fixture.position?.wrappedValue.viewID(type: Int.self) == before)
        }
    }

    @Test func readinessReplacesProvisionalNativePositionOnlyOncePerContext() async throws {
        let fixture = NativeScrollFixture()
        fixture.initial = nil
        let host = UIHostingController(rootView: NativeScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForAsync { fixture.visible.contains(0) }
            fixture.initial = 12
            try await waitForAsync { fixture.visible.contains(12) && !fixture.visible.contains(0) }
            fixture.initial = 20
            try await waitForAsync { fixture.observedInitial == 20 }
            #expect(fixture.position?.wrappedValue.viewID(type: Int.self) == 12)
            fixture.context = 2
            try await waitForAsync { fixture.visible.contains(20) && !fixture.visible.contains(12) }
        }
    }

    @Test func delayedRemountRestoresBottomAlignmentBeforeUsingAnotherInitialTarget() async throws {
        let fixture = NativeScrollFixture()
        fixture.initial = 12
        fixture.initialAnchor = .bottom
        let host = UIHostingController(rootView: NativeScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try await show(host) { _ in
            do { try await waitForAsync {
                fixture.visible.contains(12) && fixture.frames[12]
                    .map { abs($0.maxY - (fixture.viewport.maxY)) < 1 } ==
                    true
            }
            } catch {
                throw TestHostError(
                    "Initial bottom: visible=\(fixture.visible), frame=\(String(describing: fixture.frames[12])), viewport=\(fixture.viewport), inset=\(fixture.bottomInset)",
                )
            }
            fixture.mounted = false
            try await waitForAsync { fixture.visible.isEmpty }
            fixture.initial = nil
            fixture.mounted = true
            try await waitForAsync { !fixture.visible.isEmpty && fixture.observedInitial == nil }
            fixture.initial = 2
            do { try await waitForAsync {
                fixture.observedInitial == 2 && fixture.visible.contains(12)
                    && fixture.frames[12]
                    .map { abs($0.maxY - (fixture.viewport.maxY)) < 1 } ==
                    true
            }
            } catch {
                throw TestHostError(
                    "Delayed bottom: visible=\(fixture.visible), frame=\(String(describing: fixture.frames[12])), viewport=\(fixture.viewport), target=\(String(describing: fixture.position?.wrappedValue.viewID(type: Int.self))), user=\(String(describing: fixture.position?.wrappedValue.isPositionedByUser))",
                )
            }
            #expect(fixture.position?.wrappedValue.viewID(type: Int.self) == 12)
        }
    }

    @Test func replacementRetainsPositionAndContextChangeDiscardsIt() async throws {
        let fixture = ScrollFixture()
        let host = UIHostingController(rootView: ScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForAsync { fixture.bindings[.first] != nil }
            let old = try #require(fixture.bindings[.first])
            let delayedInitialization = try #require(fixture.initializers[.first])
            old.wrappedValue.scrollTo(id: 7, anchor: .top)
            fixture.mounted = false
            try await waitForAsync { fixture.disappeared }
            fixture.mounted = true
            try await waitForAsync {
                !fixture.disappeared && fixture.bindings[.first]?.wrappedValue
                    .viewID(type: Int.self) == 7
            }
            fixture.context = 2
            try await waitForAsync { fixture.observedContext == 2 }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
            old.wrappedValue.scrollTo(id: 99, anchor: .bottom)
            delayedInitialization(101)
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
            fixture.context = 1
            try await waitForAsync { fixture.observedContext == 1 }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
        }
    }

    @Test func aUserPositionUpdateSupersedesDelayedRestoration() async throws {
        let fixture = ScrollFixture()
        let host = UIHostingController(rootView: ScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForAsync { fixture.initializers[.first] != nil }
            fixture.initializers[.first]?(12)
            fixture.mounted = false
            try await waitForAsync { fixture.disappeared }
            fixture.mounted = true
            try await waitForAsync { !fixture.disappeared }
            var userPosition = ScrollPosition(id: 20, anchor: .top)
            userPosition.isPositionedByUser = true
            fixture.bindings[.first]?.wrappedValue = userPosition
            fixture.initializers[.first]?(2)
            #expect(fixture.bindings[.first]?.wrappedValue.isPositionedByUser == true)
        }
    }

    @Test func anOutgoingContextCannotReclaimTheReplacementEntryWhenItRedraws() async throws {
        let outgoing = ScrollFixture()
        let current = ScrollFixture()
        current.context = 2
        current.mounted = false
        let host = UIHostingController(rootView: VStack {
            ScrollHarness(fixture: outgoing)
            ScrollHarness(fixture: current)
        }.bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForAsync { outgoing.bindings[.first] != nil }
            outgoing.bindings[.first]?.wrappedValue.scrollTo(id: 7, anchor: .top)
            current.mounted = true
            try await waitForAsync { current.observedContext == 2 }
            current.bindings[.first]?.wrappedValue.scrollTo(id: 12, anchor: .top)
            outgoing.redraw += 1
            try await waitForAsync { outgoing.observedRedraw == 1 }
            outgoing.bindings[.first]?.wrappedValue.scrollTo(id: 99, anchor: .top)
            current.mounted = false
            try await waitForAsync { current.disappeared }
            current.mounted = true
            try await waitForAsync { !current.disappeared }
            #expect(current.bindings[.first]?.wrappedValue.viewID(type: Int.self) == 12)
        }
    }

    @Test func changingAMountedViewsRoleUsesTheNewEntry() async throws {
        let fixture = ScrollFixture()
        let host = UIHostingController(rootView: ScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForAsync { fixture.bindings[.first] != nil }
            fixture.bindings[.first]?.wrappedValue.scrollTo(id: 7, anchor: .top)
            fixture.primaryRole = .third
            try await waitForAsync { fixture.bindings[.third] != nil }
            #expect(fixture.bindings[.third]?.wrappedValue.viewID(type: Int.self) == nil)
            fixture.bindings[.third]?.wrappedValue.scrollTo(id: 12, anchor: .top)
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == 7)
        }
    }

    @Test func rolesAndScopesRemainIndependent() async throws {
        let first = ScrollFixture()
        let second = ScrollFixture()
        let host = UIHostingController(rootView: VStack {
            ScrollHarness(fixture: first).bScrollRestorationScope()
            ScrollHarness(fixture: second).bScrollRestorationScope()
        })
        try await show(host) { _ in
            try await waitForAsync { first.bindings.count == 2 && second.bindings.count == 2 }
            first.bindings[.first]?.wrappedValue.scrollTo(id: 8, anchor: .top)
            #expect(first.bindings[.second]?.wrappedValue.viewID(type: Int.self) == nil)
            #expect(second.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
        }
    }

    @Test func missingScopeUsesViewLocalState() async throws {
        let fixture = ScrollFixture()
        let host = UIHostingController(rootView: ScrollHarness(fixture: fixture))
        try await show(host) { _ in
            try await waitForAsync { fixture.bindings[.first] != nil }
            fixture.bindings[.first]?.wrappedValue.scrollTo(id: 4, anchor: .top)
            fixture.redraw += 1
            try await waitForAsync { fixture.observedRedraw == 1 }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == 4)
            fixture.mounted = false
            try await waitForAsync { fixture.disappeared }
            fixture.mounted = true
            try await waitForAsync { !fixture.disappeared }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
        }
    }
}

private enum ScrollRole: Hashable { case first, second, third }

@MainActor @Observable
private final class ScrollFixture {
    var primaryRole = ScrollRole.first
    var mounted = true
    var context = 1
    var redraw = 0
    @ObservationIgnored var observedContext: Int?
    @ObservationIgnored var observedRedraw: Int?
    @ObservationIgnored var disappeared = false
    @ObservationIgnored var bindings: [ScrollRole: Binding<ScrollPosition>] = [:]
    @ObservationIgnored var initializers: [ScrollRole: @MainActor (Int) -> Void] = [:]
}

private struct ScrollHarness: View {
    let fixture: ScrollFixture
    var body: some View {
        if fixture.mounted {
            ScrollProbe(
                fixture: fixture,
                role: fixture.primaryRole,
                context: fixture.context,
                redraw: fixture.redraw,
            )
            ScrollProbe(
                fixture: fixture,
                role: .second,
                context: fixture.context,
                redraw: fixture.redraw,
            )
        }
    }
}

private struct ScrollProbe: View {
    let fixture: ScrollFixture
    let role: ScrollRole
    let context: Int
    let redraw: Int
    @BScrollPosition<Int, Int> private var position: ScrollPosition

    init(fixture: ScrollFixture, role: ScrollRole, context: Int, redraw: Int) {
        self.fixture = fixture
        self.role = role
        self.context = context
        self.redraw = redraw
        _position = BScrollPosition(Self.self, role: role, context: context, idType: Int.self)
    }

    var body: some View {
        Color.clear.frame(height: 10)
            .onChange(of: context, initial: true) {
                captureBinding()
                if role == .first { fixture.observedContext = context }
            }
            .onChange(of: role) { captureBinding() }
            .onChange(of: redraw, initial: true) { fixture.observedRedraw = redraw }
            .onAppear { fixture.disappeared = false }
            .onDisappear { fixture.disappeared = true }
    }

    private func captureBinding() {
        fixture.bindings[role] = $position
        fixture.initializers[role] = { _position.initialize(id: $0, anchor: .bottom) }
    }
}

@MainActor @Observable
private final class NativeScrollFixture {
    var mounted = true
    var context = 1
    var initial: Int? = 0
    var initialAnchor = UnitPoint.top
    @ObservationIgnored var frames: [Int: CGRect] = [:]
    @ObservationIgnored var viewport = CGRect.zero
    @ObservationIgnored var bottomInset: CGFloat = 0
    @ObservationIgnored var observedInitial: Int?
    @ObservationIgnored var position: Binding<ScrollPosition>?
    @ObservationIgnored var visible: [Int] = []
}

private struct NativeScrollHarness: View {
    let fixture: NativeScrollFixture
    var body: some View {
        if fixture.mounted { NativeScrollProbe(fixture: fixture) }
    }
}

private struct NativeScrollProbe: View {
    let fixture: NativeScrollFixture
    @BScrollPosition<Int, Int> private var position: ScrollPosition

    init(fixture: NativeScrollFixture) {
        self.fixture = fixture
        _position = BScrollPosition(
            Self.self,
            role: ScrollRole.first,
            context: { fixture.context },
            idType: Int.self,
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(0 ..< 30, id: \.self) { index in
                    Text(index.formatted()).frame(height: 80).id(index)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            fixture.frames[index] = $0
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.bottom } action: { _, value in
            fixture.bottomInset = value
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            fixture.viewport = $0
        }
        .onScrollTargetVisibilityChange(idType: Int.self) { fixture.visible = $0 }
        .onChange(of: fixture.context, initial: true) {
            fixture.position = $position
        }
        .task(id: Readiness(context: fixture.context, initial: fixture.initial)) { initialize() }
        .onDisappear {
            fixture.visible = []
            fixture.frames = [:]
        }
    }

    private struct Readiness: Equatable {
        let context: Int
        let initial: Int?
    }

    private func initialize() {
        if let initial = fixture.initial { _position.initialize(
            id: initial,
            anchor: fixture.initialAnchor,
        ) }
        fixture.observedInitial = fixture.initial
    }
}
