@testable import PortholeGenerator
import Testing

struct SourceScannerTests {
    @Test func enumInspectionHasAStableReceiverIdentityAndOwnConditions() throws {
        let source = """
        #if DEBUG
        private enum State {
            case empty
            #if os(iOS)
            case value(Int)
            #else
            case title(String)
            #endif
        }
        #else
        private enum State { case disabled }
        #endif
        """
        func scan(_ source: String) throws -> SourceModule {
            try SourceScanner().scan(moduleName: "Fixture", files: [
                .init(path: "Fixture.swift", content: source),
            ])
        }
        let module = try scan(source)
        let inspections = module.declarations.filter { $0.kind == .enumerationInspection }
        #expect(inspections.count == 2)
        #expect(inspections.allSatisfy {
            $0.name == "$inspect" && $0.owner == "State" && !$0.isStatic &&
                $0.parameters.isEmpty && $0.resultType == "PortholeValue"
        })
        let planner = BindingPlanner(module: module, dependencyModules: [])
        #expect(planner.enumCases(for: inspections[0]).map(\.name) == ["empty", "value", "title"])
        #expect(planner.enumCases(for: inspections[1]).map(\.name) == ["disabled"])
        #expect(planner.enumCases(for: inspections[0]).filter { $0.name != "empty" }
            .allSatisfy { $0.conditions.count == 2 })
        let edited = try scan("\nfunc unrelated() {}\n" + source)
        #expect(edited.declarations.filter { $0.kind == .enumerationInspection }
            .map(\.declarationID) == inspections.map(\.declarationID))
    }

    @Test func ignoredFunctionAndInitializerArgumentsHaveDistinctKeys() throws {
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [
            .init(path: "Fixture.swift", content: """
            func ignored(_ _: Int, _ _: String) {}
            func repeatLabel(value first: Int, value second: String, for name: String) {}
            func colliding(_ value: Int, value other: String) {}
            struct Value: Sendable {
                init(_ _: Int, _ _: String, _ argument0: Bool) {}
            }
            """),
        ])
        let function = try #require(module.declarations.first { $0.name == "ignored" })
        #expect(function.parameters.map(\.label) == ["_", "_"])
        #expect(function.parameters.map(\.name) == ["argument0", "argument1"])
        let initializer = try #require(module.declarations.first { $0.kind == .initializer })
        #expect(initializer.parameters.map(\.label) == ["_", "_", "_"])
        #expect(initializer.parameters.map(\.name) == ["argument0_", "argument1", "argument0"])
        let repeated = try #require(module.declarations.first { $0.name == "repeatLabel" })
        #expect(repeated.parameters.map(\.label) == ["value", "value", "for"])
        #expect(repeated.parameters.map(\.name) == ["first", "second", "for"])
        let colliding = try #require(module.declarations.first { $0.name == "colliding" })
        #expect(colliding.parameters.map(\.label) == ["_", "value"])
        #expect(colliding.parameters.map(\.name) == ["argument0", "value"])
    }

    @Test func repeatedDeclarationsKeepUniqueStableOccurrenceIdentities() throws {
        let source = """
        protocol ValueSource {
            associatedtype Value
            var count: Int { get }
            func read() -> Int
        }
        extension ValueSource {
            var count: Int { 1 }
            func read() -> Int { 1 }
        }
        extension ValueSource where Value == Int {
            func read() -> Int { 2 }
        }
        extension ValueSource where Value == String {
            func read() -> Int { 3 }
        }
        """
        func scan(_ text: String) throws -> SourceModule {
            try SourceScanner().scan(moduleName: "Fixture", files: [
                .init(path: "Fixture.swift", content: text),
            ])
        }
        let module = try scan(source)
        let identities = module.declarations.map(\.declarationID)
        #expect(Set(identities).count == identities.count)
        let extensions = module.declarations.filter { $0.kind == .typeExtension }
        #expect(extensions.count == 3)
        let extensionBase = "Fixture:Fixture.swift:ValueSource:typeExtension:extension ValueSource"
        #expect(extensions.map(\.declarationID) == [
            extensionBase,
            extensionBase + ":occurrence:2",
            extensionBase + ":occurrence:3",
        ])
        let readers = module.declarations.filter { $0.name == "read" }
        #expect(readers.count == 4)
        let readBase = "Fixture:Fixture.swift:ValueSource.read:function:() -> Int"
        #expect(readers.map(\.declarationID) == [
            readBase,
            readBase + ":occurrence:2",
            readBase + ":occurrence:3",
            readBase + ":occurrence:4",
        ])
        let counts = module.declarations.filter { $0.name == "count" }
        #expect(counts.count == 2)
        #expect(counts.last?.declarationID == counts.first
            .map { $0.declarationID + ":occurrence:2" })
        #expect(readers.suffix(2)
            .allSatisfy { $0.unsupportedReason?.contains("Constrained extension") == true })
        let edited =
            try scan("// An unrelated declaration and line edits.\n\nfunc unrelated() {}\n" +
                source)
        #expect(edited.declarations.filter { $0.name != "unrelated" }
            .map(\.declarationID) == identities)
        #expect(edited.declarations.last?.line != module.declarations.last?.line)
    }

    @Test func enumCasesDescribeStaticConstructionAndUniquePayloadKeys() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            private enum Choice: Sendable {
                case idle, `default`
                case title(label: String = "untitled")
                case pair(Int, Int)
                case collision(Int, argument0: Int)
                case escaped(`repeat`: Int)
                #if DEBUG
                case debugOnly(String)
                #endif
            }
            """)],
        )
        let cases = module.declarations.filter { $0.kind == .enumerationCase }
        #expect(cases.count == 7)
        #expect(cases
            .allSatisfy { $0.isStatic && $0.resultType == "Choice" && $0.unsupportedReason == nil })
        #expect(cases.contains { $0.name == "default" })
        let title = try #require(cases.first { $0.name == "title" })
        #expect(title.parameters.map(\.label) == ["label"])
        #expect(title.parameters.map(\.name) == ["label"])
        #expect(title.parameters.first?.defaultValue == "\"untitled\"")
        let pair = try #require(cases.first { $0.name == "pair" })
        #expect(pair.parameters.map(\.label) == ["_", "_"])
        #expect(pair.parameters.map(\.name) == ["argument0", "argument1"])
        let collision = try #require(cases.first { $0.name == "collision" })
        #expect(collision.parameters.map(\.label) == ["_", "argument0"])
        #expect(collision.parameters.map(\.name) == ["argument0_", "argument0"])
        let escaped = try #require(cases.first { $0.name == "escaped" })
        #expect(escaped.parameters.map(\.label) == ["repeat"])
        #expect(escaped.parameters.map(\.name) == ["repeat"])
        #expect(cases.first { $0.name == "debugOnly" }?.conditions.isEmpty == false)
    }

    @Test func unsupportedEnumPayloadsKeepTheirNamesAndSourceReasons() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            enum Event { case callback(handler: @Sendable () -> Void) }
            enum Generic<T> { case value(T) }
            """)],
        )
        let callback = try #require(module.declarations.first { $0.name == "callback" })
        #expect(callback.unsupportedReason?.contains("Associated value 'handler'") == true)
        #expect(callback.unsupportedReason?.contains("executable callback binding") == true)
        let generic = try #require(module.declarations.first { $0.name == "value" })
        #expect(generic.unsupportedReason == "Generic type requires a concrete specialization.")
        #expect(!module.declarations
            .contains { $0.unsupportedReason?.contains("value codec") == true })
    }

    @Test func nestedNominalTypesDoNotInheritGlobalActorIsolation() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            @MainActor final class Model {
                enum State { case idle }
                struct Details {
                    let title: String
                    func name() -> String { title }
                }
                @MainActor final class Isolated { func name() -> String { "isolated" } }
                var state: State = .idle
            }
            """)],
        )
        for declaration in module.declarations where
            ["Model.State", "Model.Details"].contains(declaration.resultType ?? "") ||
            declaration.owner == "Model.Details"
        {
            #expect(!declaration.isMainActor)
        }
        #expect(module.declarations.first { $0.name == "state" }?.isMainActor == true)
        #expect(module.declarations.first { $0.name == "Isolated" }?.isMainActor == true)
        #expect(module.declarations.first { $0.owner == "Model.Isolated" }?.isMainActor == true)
    }

    @Test func previewClosuresDoNotExportLocalStateOrLocalTypes() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            struct Control { static let title: String = "Control" }
            #Preview {
                @Previewable @State var value: Double = 0
                struct Local { var count: Int = 0 }
                Control()
            }
            """)],
        )
        #expect(module.declarations.map(\.name) == ["Control", "title"])
    }

    @Test func distinguishesComputedGetterBodyFromSetterDeclaration() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            actor Model {
                var offset: Int { let reset = 3; return reset }
                var observed: Int = 0 { didSet {} }
                var asynchronous: Int { get async throws { 4 } }
            }
            """)],
        )
        #expect(!module.declarations.contains { $0.name == "offset" && $0.kind == .propertySetter })
        #expect(module.declarations
            .contains { $0.name == "observed" && $0.kind == .propertySetter })
        let getter = try #require(module.declarations.first { $0.name == "asynchronous" })
        #expect(getter.isAsync && getter.isThrowing)
    }

    @Test func inventoriesPrivateMembersAndSkipsFunctionLocals() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [SourceFile(path: "Fixture.swift", content: """
            actor Engine {
                private var count: Int = 0
                private func advance(by amount: Int) async throws -> Int {
                    let local = amount
                    return local
                }
            }
            """)],
        )
        #expect(module.declarations.map(\.name) == ["Engine", "count", "count", "advance"])
        let method = try #require(module.declarations.last)
        #expect(method.access == "private")
        #expect(method.isActor)
        #expect(method.isAsync)
        #expect(method.isThrowing)
        #expect(method.line == 3)
    }

    @Test func diagnosesPrivateIdentityCollisionsAcrossFiles() throws {
        #expect(throws: GeneratorError.self) {
            try SourceScanner().scan(moduleName: "Fixture", files: [
                SourceFile(path: "One.swift", content: "private struct Hidden {}"),
                SourceFile(path: "Two.swift", content: "private struct Hidden {}"),
            ])
        }
    }

    @Test func retainsConditionalBranches() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [SourceFile(path: "Fixture.swift", content: """
            #if os(iOS)
            func platform() -> Int { 1 }
            #elseif DEBUG
            func fallback() -> Int { 2 }
            #else
            func other() -> Int { 3 }
            #endif
            """)],
        )
        #expect(module.declarations[0].conditions == ["(os(iOS))"])
        #expect(module.declarations[1].conditions == ["!(os(iOS)) && (DEBUG)"])
        #expect(module.declarations[2].conditions == ["!(os(iOS)) && !(DEBUG)"])
    }
}
