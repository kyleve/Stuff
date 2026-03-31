@testable import BroadwayCore
import Testing

// MARK: - Test Fixtures

private enum ColorTheme: String, BTheme {
    static let defaultValue: Self = .light

    case light, dark
}

private struct TestStylesheet: BStylesheet {
    var color: ColorTheme

    init(context: SlicingContext) {
        color = context.themes[ColorTheme.self]
    }
}

private struct BaseStylesheet: BStylesheet {
    var color: ColorTheme

    init(context: SlicingContext) {
        color = context.themes[ColorTheme.self]
    }
}

private struct DerivedStylesheet: BStylesheet {
    var baseColor: ColorTheme

    init(context: SlicingContext) throws {
        baseColor = try context.stylesheets.get(BaseStylesheet.self).color
    }
}

private struct LeafStylesheet: BStylesheet {
    var baseColor: ColorTheme

    init(context: SlicingContext) throws {
        baseColor = try context.stylesheets.get(DerivedStylesheet.self).baseColor
    }
}

private struct CountingStylesheet: BStylesheet, Equatable {
    static var initCount = 0

    var color: ColorTheme

    init(context: SlicingContext) {
        Self.initCount += 1
        color = context.themes[ColorTheme.self]
    }
}

private struct CycleA: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(CycleB.self)
    }
}

private struct CycleB: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(CycleA.self)
    }
}

private struct SelfCycle: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(SelfCycle.self)
    }
}

private struct CycleC: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(CycleA.self)
    }
}

private struct ThreeNodeCycleA: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(ThreeNodeCycleB.self)
    }
}

private struct ThreeNodeCycleB: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(ThreeNodeCycleC.self)
    }
}

private struct ThreeNodeCycleC: BStylesheet {
    init(context: SlicingContext) throws {
        _ = try context.stylesheets.get(ThreeNodeCycleA.self)
    }
}

private struct FailingError: Error, Equatable {}

private struct FailingStylesheet: BStylesheet {
    init(context _: SlicingContext) throws {
        throw FailingError()
    }
}

struct BContextStylesheetTests {
    private func makeContext(
        traits: BTraits = .init(),
        themes: BThemes = .init(),
    ) -> BContext {
        BContext(traits: traits, themes: themes)
    }

    // MARK: - Lazy Creation

    @Test("Accessing a stylesheet creates it lazily from context")
    func lazyCreation() throws {
        var themes = BThemes()
        themes[ColorTheme.self] = .dark

        let context = makeContext(themes: themes)
        let sheet = try context.stylesheets.get(TestStylesheet.self)

        #expect(sheet.color == .dark)
    }

    // MARK: - Caching

    @Test("Accessing the same stylesheet twice returns an equal value")
    func caching() throws {
        let context = makeContext()

        let first = try context.stylesheets.get(TestStylesheet.self)
        let second = try context.stylesheets.get(TestStylesheet.self)

        #expect(first == second)
    }

    // MARK: - Invalidation

    @Test("Changing themes produces a stylesheet with the new theme")
    func themeInvalidation() throws {
        var context = makeContext()

        let before = try context.stylesheets.get(TestStylesheet.self)
        #expect(before.color == .light)

        context.themes[ColorTheme.self] = .dark

        let after = try context.stylesheets.get(TestStylesheet.self)
        #expect(after.color == .dark)
    }

    @Test("Changing traits produces a fresh stylesheet")
    func traitsInvalidation() throws {
        var context = makeContext()

        let before = try context.stylesheets.get(TestStylesheet.self)

        context.traits.accessibility = BAccessibility(isVoiceOverRunning: true)

        let after = try context.stylesheets.get(TestStylesheet.self)

        // Both are default TestStylesheets (no theme set), so equal by value,
        // but the key changed so it was re-created rather than cache-hit.
        #expect(before == after)
    }

    // MARK: - Stylesheet Dependencies

    @Test("A stylesheet can depend on another stylesheet")
    func directDependency() throws {
        var themes = BThemes()
        themes[ColorTheme.self] = .dark

        let context = makeContext(themes: themes)
        let derived = try context.stylesheets.get(DerivedStylesheet.self)

        #expect(derived.baseColor == .dark)
    }

    @Test("Transitive stylesheet dependencies resolve correctly")
    func transitiveDependency() throws {
        var themes = BThemes()
        themes[ColorTheme.self] = .dark

        let context = makeContext(themes: themes)
        let leaf = try context.stylesheets.get(LeafStylesheet.self)

        #expect(leaf.baseColor == .dark)
    }

    @Test("Dependent stylesheet reflects theme changes")
    func dependencyThemeInvalidation() throws {
        var context = makeContext()

        let before = try context.stylesheets.get(DerivedStylesheet.self)
        #expect(before.baseColor == .light)

        context.themes[ColorTheme.self] = .dark

        let after = try context.stylesheets.get(DerivedStylesheet.self)
        #expect(after.baseColor == .dark)
    }

    // MARK: - Cycle Detection

    @Test("Circular stylesheet dependency throws cyclicDependency")
    func cycleThrows() {
        let stylesheets = BStylesheets(config: .init(traits: .init(), themes: .init()))

        #expect(throws: StylesheetError.self) {
            _ = try stylesheets.get(CycleA.self)
        }
    }

    @Test("cyclicDependency error includes the dependency path")
    func cyclePath() {
        let stylesheets = BStylesheets(config: .init(traits: .init(), themes: .init()))

        let error = #expect(throws: StylesheetError.self) {
            _ = try stylesheets.get(CycleA.self)
        }

        if case let .cyclicDependency(path) = error {
            #expect(path.first == "CycleA")
            #expect(path.last == "CycleA")
            #expect(path.count == 3)
        }
    }

    @Test("cyclicDependency description shows the full cycle path")
    func cycleDescription() {
        let error = StylesheetError.cyclicDependency(path: ["CycleA", "CycleB", "CycleA"])

        #expect(error.description == "Stylesheet dependency cycle: CycleA → CycleB → CycleA")
    }

    @Test("Self-referencing stylesheet throws cyclicDependency")
    func selfCycle() {
        let stylesheets = BStylesheets(config: .init(traits: .init(), themes: .init()))

        #expect(throws: StylesheetError.self) {
            _ = try stylesheets.get(SelfCycle.self)
        }
    }

    @Test("Three-node cycle throws cyclicDependency with full path")
    func threeNodeCycle() {
        let stylesheets = BStylesheets(config: .init(traits: .init(), themes: .init()))

        let error = #expect(throws: StylesheetError.self) {
            _ = try stylesheets.get(ThreeNodeCycleA.self)
        }

        if case let .cyclicDependency(path) = error {
            #expect(path.count == 4)
            #expect(path.first == "ThreeNodeCycleA")
            #expect(path.last == "ThreeNodeCycleA")
        }
    }

    @Test("Non-cycle error wraps in creationFailed")
    func nonCycleThrow() {
        let stylesheets = BStylesheets(config: .init(traits: .init(), themes: .init()))

        let error = #expect(throws: StylesheetError.self) {
            _ = try stylesheets.get(FailingStylesheet.self)
        }

        if case let .creationFailed(_, underlying) = error {
            #expect(underlying is FailingError)
        }
    }

    @Test("set() stores a stylesheet that get() returns")
    func setAndGet() throws {
        var themes = BThemes()
        themes[ColorTheme.self] = .dark
        let source = BStylesheets(config: .init(traits: .init(), themes: themes))
        let sheet = try source.get(TestStylesheet.self)

        var target = BStylesheets(config: .init(traits: .init(), themes: themes))
        target.set(sheet)

        let retrieved = try target.get(TestStylesheet.self)
        #expect(retrieved == sheet)
    }

    @Test("Changing traits re-creates the stylesheet")
    func traitsInvalidationProvenByCounter() throws {
        CountingStylesheet.initCount = 0

        var context = BContext()
        _ = try context.stylesheets.get(CountingStylesheet.self)
        #expect(CountingStylesheet.initCount == 1)

        context.traits.accessibility = BAccessibility(isVoiceOverRunning: true)
        _ = try context.stylesheets.get(CountingStylesheet.self)
        #expect(CountingStylesheet.initCount == 2)
    }
}

// MARK: - BContext Tests

struct BContextTests {
    @Test("Default init produces equal instances")
    func defaultEquality() {
        #expect(BContext() == BContext())
    }

    @Test("Contexts with different traits are not equal")
    func traitInequality() {
        var a = BContext()
        a.traits.accessibility = BAccessibility(isVoiceOverRunning: true)
        #expect(a != BContext())
    }

    @Test("Contexts with different themes are not equal")
    func themeInequality() {
        var a = BContext()
        a.themes[ColorTheme.self] = .dark
        #expect(a != BContext())
    }

    @Test("Trait mutation propagates to stylesheets config")
    func traitPropagation() {
        var context = BContext()
        let accessibility = BAccessibility(isVoiceOverRunning: true)
        context.traits.accessibility = accessibility
        #expect(context.stylesheets.traits.accessibility == accessibility)
    }

    @Test("Theme mutation propagates to stylesheets config")
    func themePropagation() {
        var context = BContext()
        context.themes[ColorTheme.self] = .dark

        let theme: ColorTheme = context.stylesheets.themes[ColorTheme.self]
        #expect(theme == .dark)
    }
}
