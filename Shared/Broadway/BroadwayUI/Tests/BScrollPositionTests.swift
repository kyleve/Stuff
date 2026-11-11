import BroadwayUI
import Observation
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct BScrollPositionTests {
    @Test func nativeScrollViewRestoresItsVisibleTargetAfterReplacement() throws {
        let fixture = NativeScrollFixture()
        fixture.initial = nil
        let host = UIHostingController(rootView: NativeScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try show(host) { controller in
            try waitFor { fixture.position != nil && fixture.visible.contains(0) }
            fixture.position?.wrappedValue.scrollTo(id: 12, anchor: .top)
            try waitFor { fixture.visible.contains(12) && !fixture.visible.contains(0) }
            let before = fixture.position?.wrappedValue.viewID(type: Int.self)
            fixture.mounted = false
            try waitFor { fixture.visible.isEmpty }
            fixture.mounted = true
            controller.view.layoutIfNeeded()
            try waitFor { fixture.visible.contains(12) && !fixture.visible.contains(0) }
            #expect(fixture.position?.wrappedValue.viewID(type: Int.self) == before)
        }
    }

    @Test func readinessReplacesProvisionalNativePositionOnlyOncePerContext() throws {
        let fixture = NativeScrollFixture()
        fixture.initial = nil
        let host = UIHostingController(rootView: NativeScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try show(host) { _ in
            try waitFor { fixture.visible.contains(0) }
            fixture.initial = 12
            try waitFor { fixture.visible.contains(12) && !fixture.visible.contains(0) }
            fixture.initial = 20
            try waitFor { fixture.observedInitial == 20 }
            #expect(fixture.position?.wrappedValue.viewID(type: Int.self) == 12)
            fixture.context = 2
            try waitFor { fixture.visible.contains(20) && !fixture.visible.contains(12) }
        }
    }

    @Test func replacementRetainsPositionAndContextChangeDiscardsIt() throws {
        let fixture = ScrollFixture()
        let host = UIHostingController(rootView: ScrollHarness(fixture: fixture)
            .bScrollRestorationScope())
        try show(host) { _ in
            try waitFor { fixture.bindings[.first] != nil }
            let old = try #require(fixture.bindings[.first])
            old.wrappedValue.scrollTo(id: 7, anchor: .top)
            fixture.mounted = false
            try waitFor { fixture.disappeared }
            fixture.mounted = true
            try waitFor {
                !fixture.disappeared && fixture.bindings[.first]?.wrappedValue
                    .viewID(type: Int.self) == 7
            }
            fixture.context = 2
            try waitFor { fixture.observedContext == 2 }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
            old.wrappedValue.scrollTo(id: 99, anchor: .bottom)
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
            fixture.context = 1
            try waitFor { fixture.observedContext == 1 }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
        }
    }

    @Test func rolesAndScopesRemainIndependent() throws {
        let first = ScrollFixture()
        let second = ScrollFixture()
        let host = UIHostingController(rootView: VStack {
            ScrollHarness(fixture: first).bScrollRestorationScope()
            ScrollHarness(fixture: second).bScrollRestorationScope()
        })
        try show(host) { _ in
            try waitFor { first.bindings.count == 2 && second.bindings.count == 2 }
            first.bindings[.first]?.wrappedValue.scrollTo(id: 8, anchor: .top)
            #expect(first.bindings[.second]?.wrappedValue.viewID(type: Int.self) == nil)
            #expect(second.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
        }
    }

    @Test func missingScopeUsesViewLocalState() throws {
        let fixture = ScrollFixture()
        let host = UIHostingController(rootView: ScrollHarness(fixture: fixture))
        try show(host) { _ in
            try waitFor { fixture.bindings[.first] != nil }
            fixture.bindings[.first]?.wrappedValue.scrollTo(id: 4, anchor: .top)
            fixture.redraw += 1
            try waitFor { fixture.observedRedraw == 1 }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == 4)
            fixture.mounted = false
            try waitFor { fixture.disappeared }
            fixture.mounted = true
            try waitFor { !fixture.disappeared }
            #expect(fixture.bindings[.first]?.wrappedValue.viewID(type: Int.self) == nil)
        }
    }
}

private enum ScrollRole: Hashable { case first, second }

@MainActor @Observable
private final class ScrollFixture {
    var mounted = true
    var context = 1
    var redraw = 0
    @ObservationIgnored var observedContext: Int?
    @ObservationIgnored var observedRedraw: Int?
    @ObservationIgnored var disappeared = false
    @ObservationIgnored var bindings: [ScrollRole: Binding<ScrollPosition>] = [:]
}

private struct ScrollHarness: View {
    let fixture: ScrollFixture
    var body: some View {
        if fixture.mounted {
            ScrollProbe(
                fixture: fixture,
                role: .first,
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
    @BScrollPosition<Int> private var position: ScrollPosition

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
                fixture.bindings[role] = $position
                if role == .first { fixture.observedContext = context }
            }
            .onChange(of: redraw, initial: true) { fixture.observedRedraw = redraw }
            .onAppear { fixture.disappeared = false }
            .onDisappear { fixture.disappeared = true }
    }
}

@MainActor @Observable
private final class NativeScrollFixture {
    var mounted = true
    var context = 1
    var initial: Int? = 0
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
    @BScrollPosition<Int> private var position: ScrollPosition

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
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onScrollTargetVisibilityChange(idType: Int.self) { fixture.visible = $0 }
        .onChange(of: fixture.context, initial: true) {
            fixture.position = $position
            initialize()
        }
        .onChange(of: fixture.initial) { initialize() }
        .onDisappear { fixture.visible = [] }
    }

    private func initialize() {
        if let initial = fixture.initial { _position.initialize(ScrollPosition(
            id: initial,
            anchor: .top,
        )) }
        fixture.observedInitial = fixture.initial
    }
}
