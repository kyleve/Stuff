import Foundation
@testable import PortholeGenerator
import SwiftParser
import SwiftSyntax
import Testing

struct BindingEmitterTests {
    @Test func ignoredArgumentsDecodeIndependentKeysWithExplicitTypes() throws {
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [
            .init(path: "Fixture.swift", content: """
            func ignored(_ _: Int, _ _: String) -> String { "called" }
            func repeatLabel(value first: Int, value second: String, for name: String) -> String { second + name }
            func empty(_ _: Void) {}
            """),
        ])
        let emitted = try BindingEmitter(planner: .init(module: module, dependencyModules: []))
            .emit()
        #expect(emitted.contains("invocation.arguments[\"argument0\"]"))
        #expect(emitted.contains("invocation.arguments[\"argument1\"]"))
        #expect(!emitted.contains("invocation.arguments[\"_\"]"))
        #expect(emitted.contains("let value0: Int = try await registry.decode"))
        #expect(emitted.contains("let value1: String = try await registry.decode"))
        #expect(emitted.contains("guard argument0 == .null"))
        #expect(emitted.contains("let value0: Void = ()"))
        #expect(emitted.contains("`ignored`(value0, value1)"))
        #expect(emitted.contains("invocation.arguments[\"first\"]"))
        #expect(emitted.contains("invocation.arguments[\"second\"]"))
        #expect(emitted.contains("invocation.arguments[\"for\"]"))
        #expect(emitted.contains("`repeatLabel`(value: value0, value: value1, for: value2)"))
    }

    @Test func enumConstructionPreservesLabelsAndAlwaysRetainsTypedResults() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            enum Choice: Sendable, Codable {
                case `default`
                case title(label: String)
                case pair(Int, Int)
                case collision(Int, argument0: Int)
                case escaped(`repeat`: Int)
            }
            enum Plain { case title(String) }
            """)],
        )
        let emitted = try BindingEmitter(planner: .init(module: module, dependencyModules: []))
            .emit()
        #expect(emitted.contains("Choice.`default` }()"))
        #expect(emitted.contains("Choice.`title`(label: value0)"))
        #expect(emitted.contains("Choice.`pair`(value0, value1)"))
        #expect(emitted.contains("Choice.`collision`(value0, argument0: value1)"))
        #expect(emitted.contains("Choice.`escaped`(repeat: value0)"))
        #expect(emitted.contains("name: \"argument0_\", summary: \"Int\""))
        #expect(emitted.contains("name: \"argument0\", summary: \"argument0: Int\""))
        #expect(emitted
            .contains("registry.retain(result, in: invocation.scope, retention: .results)"))
        #expect(emitted.contains("registry.encodeMainActor(PortholeMainActorValue(result)"))
        #expect(!emitted.contains("registry.encode(result, in: invocation.scope)"))
        #expect(emitted.contains("result: .any, effect: .unknown"))
        #expect(emitted.contains("case let .`escaped`(repeat: payload0):"))
    }

    @Test func enumInspectionUsesTypedReadsAndNeverApplicationSerialization() throws {
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [
            .init(path: "Fixture.swift", content: """
            struct Payload: Sendable, Encodable { let value: String }
            enum Packet: Sendable, Encodable {
                case empty
                case exact(UInt64, Int64)
                case complex(Payload)
                #if DEBUG
                case debug(String)
                #else
                case release(Double)
                #endif
            }
            """),
        ])
        let generated = try BindingEmitter(planner: .init(module: module, dependencyModules: []))
            .emit()
        #expect(!Parser.parse(source: generated).hasError)
        #expect(generated.contains("name: \"Packet.$inspect\""))
        #expect(generated.contains("switch receiver {"))
        #expect(generated.contains("case .`empty`:"))
        #expect(generated.contains(".unsignedInteger(UInt64(payload0))"))
        #expect(generated.contains(".integer(Int64(payload1))"))
        #expect(generated
            .contains("registry.retain(payload0, in: invocation.scope, retention: .results)"))
        #expect(!generated.contains("registry.encode(payload"))
        #expect(!generated.contains("Mirror("))
        #expect(generated.contains("guard payload0.isFinite else"))
        let tree = Parser.parse(source: generated)
        let moduleType = try #require(tree.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
            .first)
        // Invocation bodies live inside the original-source compilation guard.
        // Walk through conditional declarations before locating the actual inspector.
        final class InspectorVisitor: SyntaxVisitor {
            var inspector: FunctionDeclSyntax?

            init() {
                super.init(viewMode: .sourceAccurate)
            }

            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if inspector == nil, node.description.contains("switch receiver") {
                    inspector = node
                }
                return .skipChildren
            }
        }
        let visitor = InspectorVisitor()
        visitor.walk(moduleType)
        let inspector = try #require(visitor.inspector)
        #expect(inspector.description.contains("#if ((DEBUG))"))
        #expect(inspector.description.contains("#if (!(DEBUG))"))
    }

    @Test func largeMetadataCatalogUsesBoundedSynchronousRegistryBatches() throws {
        let source = (0 ..< 512).map {
            "func metadata\($0)<T>(_ value: T) -> T { value }"
        }.joined(separator: "\n")
        let module = try SourceScanner().scan(
            moduleName: "LargeFixture",
            files: [.init(path: "LargeFixture.swift", content: source)],
        )
        let generated = try BindingEmitter(planner: .init(module: module, dependencyModules: []))
            .emit()
        let tree = Parser.parse(source: generated)
        let container = try #require(tree.statements.compactMap {
            $0.item.as(EnumDeclSyntax.self)
        }.first)
        let functions = container.memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }
        let batches = functions.filter { $0.name.text.hasPrefix("installBatch") }
        let sizes = batches.map { function in
            function.body?.statements.compactMap { $0.item.as(VariableDeclSyntax.self) }.count ?? 0
        }
        #expect(sizes.reduce(0, +) == 512)
        #expect(sizes.allSatisfy { (1 ... 16).contains($0) })
        for batch in batches {
            #expect(batch.signature.effectSpecifiers?.asyncSpecifier == nil)
            #expect(batch.signature.parameterClause.parameters.first?.type
                .trimmedDescription == "isolated PortholeRegistry")
            #expect(!batch.tokens(viewMode: .sourceAccurate)
                .contains { $0.tokenKind == .keyword(.await) })
        }
        let installer = try #require(functions.first { $0.name.text == "install" })
        #expect(installer.body?.statements.contains { $0.item.is(ForStmtSyntax.self) } == true)
        #expect(generated
            .contains("{ registry, scope in try await installBatch0(registry, scope) }"))
        #expect(!generated.contains("        installBatch0,"))
        let lastStatement = try #require(installer.body?.statements.last)
        #expect(lastStatement.description
            .contains("registry.installCoverage(coverageJSON, in: scope)"))
    }

    @Test(arguments: ["Character?", "Substring?", "[Character]"])
    func containersWithoutJSONCodecsAdvertiseTypedReferences(type: String) throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(
                path: "Fixture.swift",
                content: "func echo(_ value: \(type)) -> \(type) { value }",
            )],
        )
        let emitted = try BindingEmitter(planner: .init(module: module, dependencyModules: []))
            .emit()
        #expect(emitted.contains("summary: \"\(type)\", schema: .any"))
        #expect(emitted.contains("result: .any, effect: .unknown"))
    }

    @Test func privateAccessFlagStillRejectsInvalidActorAccess() throws {
        try GeneratorCompilerTestSupport.rejectInvalidIsolation()
    }

    @Test func emittedPrivateMembersIndexLinkAndRunInDebugAndOptimizedBuilds() throws {
        let source = """
        import SwiftUI
        extension View {
            func fixtureLabel() -> String { "view" }
        }
        final class Journal: @unchecked Sendable {
            private let count: Int
            private init(count: Int) { self.count = count }
            private func double() -> Int { count * 2 }
        }
        extension Journal { private var first: Int { count } }
        extension Journal { private var second: Int { count } }
        actor Engine {
            private let identity: String = "engine"
            private var count: Int
            private init(count: Int) { self.count = count }
            private func doubled() -> Int { count * 2 }
            private func doubled() async -> Int { 999 }
        }
        @MainActor final class Editor {
            private enum State { case idle, loaded(Int) }
            private struct Details {
                var title: String
                init(title: String) { self.title = title }
            }
            private var count: Int
            private var state: State = .idle
            private var details: Details = Details(title: "fixture")
            private var stateCount: Int {
                switch state {
                    case .idle: 0
                    case let .loaded(count): count
                }
            }
            private init(count: Int) { self.count = count }
        }
        struct InspectorFixtureView: View {
            var body: some View { EmptyView() }
            private init() {}
            private static var title: String { "inspector" }
            private static func paletteIndex(for name: String) -> Int { name.count }
        }
        private struct CounterValue: Sendable {
            private var count: Int
            private init(count: Int) { self.count = count }
            private mutating func advance() { count += 1 }
        }
        protocol AsyncObserver: Sendable { func read() async -> Int }
        @MainActor protocol ValueObserver: AnyObject, AsyncObserver {
            func read() -> Int
        }
        @MainActor final class PlainObserver: ValueObserver {
            func read() -> Int { 11 }
        }
        @MainActor protocol MainActorOnlyObserver: AnyObject {
            func read() -> Int
        }
        extension MainActorOnlyObserver { func read() -> Int { 12 } }
        @MainActor final class MainActorOnlyImplementation: MainActorOnlyObserver {
            func read() -> Int { 13 }
        }
        @MainActor final class ObserverHolder {
            private let observer: any ValueObserver = PlainObserver()
            private var observers: [any ValueObserver] = [PlainObserver()]
            private let isolatedObserver: any MainActorOnlyObserver = MainActorOnlyImplementation()
            private init() {}
            private func clearObservers() { observers = [] }
            private func echo(_ value: any MainActorOnlyObserver) -> any MainActorOnlyObserver { value }
        }
        private enum Packet: Sendable {
            case empty
            case pair(Int, Int)
            case labeled(title: String, count: Int)
            case collision(Int, argument0: Int)
            case escaped(`repeat`: Int)
            case `default`
            private var total: Int {
                switch self {
                    case .empty, .default: 0
                    case let .pair(first, second), let .collision(first, second): first + second
                    case let .labeled(title, count): title.count + count
                    case let .escaped(count): count
                }
            }
        }
        private enum WireCode: Int, Sendable, Encodable {
            case ready = 7
            func encode(to encoder: any Encoder) throws { fatalError("Case construction invoked an encoder") }
            private var number: Int { rawValue }
        }
        private enum PlainChoice {
            case note(String)
            case observer(any MainActorOnlyObserver)
            private var isNote: Bool {
                switch self {
                    case .note: true
                    case .observer: false
                }
            }
        }
        private struct EncodedPayload: Sendable, Encodable {
            private let title: String
            private init(title: String) { self.title = title }
            func encode(to encoder: any Encoder) throws { fatalError("Payload inspection invoked an encoder") }
        }
        private enum OpaquePacket: Sendable {
            case value(EncodedPayload), values([EncodedPayload])
            var trap: Int { fatalError("Enum inspection invoked a computed getter") }
        }
        private enum ScalarPacket: Sendable {
            case exact(UInt64, Int64), number(Double), empty(Void)
        }
        private enum ConditionalInspection: Sendable {
            #if DEBUG
            case debug(value: String)
            #else
            case release(value: Int)
            #endif
        }
        private enum EmptyInspection {}
        private enum UnsafeInspection { case pointer(UnsafeRawPointer) }
        private enum CallbackInspection { case handler(@Sendable () -> Void) }
        private enum AvailableInspection { @available(macOS 999, *) case future }
        @MainActor private final class GenericOwner<Launch: Sendable> {
            enum Phase { case ready(Launch) }
        }
        @MainActor extension GenericOwner.Phase {
            enum SurfaceIdentity: Sendable {
                case splash, ready
                var title: String { "surface" }
            }
            private var surfaceIdentity: SurfaceIdentity { .ready }
        }
        extension GenericOwner.Phase.SurfaceIdentity {
            private enum Nested: Sendable { case idle }
        }
        @MainActor private func inspectChoice(_ value: PlainChoice) -> Int {
            switch value {
                case let .note(text): text.count
                case let .observer(observer): observer.read()
            }
        }
        func character(_ value: Character) -> Character { value }
        func substring(_ value: Substring) -> Substring { value }
        func engines(_ values: [Engine]) -> [Engine] { values }
        func ignored(_ _: Int, _ _: String) -> String { "called" }
        func repeatLabel(value first: Int, value second: String, for name: String) -> String { String(first) + second + name }
        func empty(_ _: Void) {}
        final class NonSendableCoverage { var value = 0 }
        func unsupportedCoverage(_ value: NonSendableCoverage) -> Int { value.value }
        #if DEBUG
        func debugCoverage() -> Int { 1 }
        #else
        func releaseCoverage() -> Int { 2 }
        #endif
        """
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Original.swift", content: source)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        for declaration in module.declarations where declaration.owner?
            .hasPrefix("GenericOwner") == true || declaration.name == "GenericOwner"
        {
            #expect(planner.plan(declaration).unsupportedReason != nil)
        }
        let inventory = try SourceScanner().scan(
            moduleName: "InventoryFixture",
            files: [.init(path: "Inventory.swift", content: (0 ..< 32).map {
                "private func metadata\($0)(_ value: [String: Int]) -> Int { 0 }"
            }.joined(separator: "\n"))],
        )
        let generated = try BindingEmitter(planner: planner, inventories: [.init(
            module: inventory,
            reason: "Native control-plane source remains descriptive.",
            excludedFiles: [.init(
                path: "Credentials.swift",
                reason: "Credential implementation is excluded.",
            )],
        )]).emit()
        #expect(!generated.contains("try await registry.describe("))
        #expect(!generated.contains("try await registry.register("))
        try GeneratorCompilerTestSupport.verify(source: source, generated: generated)
    }

    @Test func emitsPrivateActorBindingsAndSourceGuard() throws {
        let source = """
        actor Engine {
            private let identity: String = "engine"
            private var count: Int = 0
            private init(count: Int) { self.count = count }
            private func advance(by amount: Int) async throws -> Int { count + amount }
        }
        """
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [SourceFile(path: "Fixture.swift", content: source)],
        )
        let emitted = try BindingEmitter(planner: BindingPlanner(
            module: module,
            dependencyModules: [],
        )).emit()
        #expect(emitted.contains("#if PORTHOLE_ORIGINAL_SOURCE_CHECK"))
        #expect(emitted.contains("registry.installSourceArchive(sourceArchiveJSON, in: scope)"))
        #expect(emitted.contains("try await receiver.`advance`(by: value0)"))
        #expect(emitted.contains("let result: Int = await receiver.`count`"))
        #expect(emitted.contains("let result: String = receiver.`identity`"))
        #expect(emitted
            .contains("registry.retain(result, in: invocation.scope, retention: .results)"))
        #expect(emitted.contains("self.`count` = value0"))
        #expect(emitted.contains("effect: .mutation"))
        #expect(emitted.contains("effect: .read"))
        #expect(emitted.contains("ownership: .actorInstance(typeName: \"Engine\")"))
        #expect(emitted.contains("ownership: .unisolated"))
    }

    @Test func preservesPlatformImportsAndEscapesSourceText() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [SourceFile(path: "Fixture.swift", content: #"""
            #if canImport(UIKit)
            import UIKit
            #else
            import Foundation
            #endif
            func text() -> String { "\(1) \"quote\"" }
            """#)],
        )
        let emitted = try BindingEmitter(planner: BindingPlanner(
            module: module,
            dependencyModules: [],
        )).emit()
        #expect(emitted.contains("#if canImport(UIKit)\nimport UIKit\n#endif"))
        #expect(emitted.contains("#if canImport(UIKit)\n#else\nimport Foundation\n#endif"))
        #expect(emitted.contains(#"\\(1)"#))
    }
}
