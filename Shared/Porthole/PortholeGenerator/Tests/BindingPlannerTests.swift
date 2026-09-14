@testable import PortholeGenerator
import Testing

struct BindingPlannerTests {
    @Test func enumInspectionPreservesPayloadAndOwnerRestrictions() throws {
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [
            .init(path: "Fixture.swift", content: """
            enum Empty {}
            enum Packet: Sendable { case empty, value(UInt64) }
            struct Payload { let title: String }
            enum Boxed { case value(Payload) }
            enum Callback { case value(handler: @Sendable () -> Void) }
            enum Pointer { case value(UnsafeRawPointer) }
            enum Generic<T> { case value(T) }
            enum Owned: ~Copyable { case empty }
            enum Versioned { @available(macOS 999, *) case future }
            enum Missing { case value(UnknownExternalType) }
            """),
        ])
        let planner = BindingPlanner(module: module, dependencyModules: [])
        let bindings = Dictionary(uniqueKeysWithValues: module.declarations
            .filter { $0.kind == .enumerationInspection }.map { ($0.owner!, planner.plan($0)) })
        #expect(bindings["Packet"]?.unsupportedReason == nil)
        #expect(bindings["Packet"]?.receiverType == "Packet")
        #expect(bindings["Packet"]?.isMainActor == false)
        #expect(bindings["Boxed"]?.unsupportedReason == nil)
        #expect(bindings["Boxed"]?.isMainActor == true)
        #expect(bindings["Empty"]?.unsupportedReason?.contains("no source-declared cases") == true)
        #expect(bindings["Callback"]?.unsupportedReason?
            .contains("Associated value 'handler'") == true)
        #expect(bindings["Pointer"]?.unsupportedReason?.contains("UnsafeRawPointer") == true)
        #expect(bindings["Generic"]?.unsupportedReason?.contains("specialization") == true)
        #expect(bindings["Owned"]?.unsupportedReason?.contains("Noncopyable") == true)
        #expect(bindings["Versioned"]?.unsupportedReason?.contains("case 'future'") == true)
        #expect(bindings["Versioned"]?.unsupportedReason?.contains("availability") == true)
        #expect(bindings["Missing"]?.unsupportedReason?.contains("UnknownExternalType") == true)
    }

    @Test func nestedTypesInGenericExtensionsRetainTheAncestorRestriction() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [
                .init(path: "Owner.swift", content: """
                @MainActor final class GenericOwner<Launch: Sendable> {
                    enum Phase { case ready(Launch) }
                }
                """),
                .init(path: "Extension.swift", content: """
                @MainActor extension GenericOwner.Phase {
                    enum SurfaceIdentity: Sendable {
                        case splash, ready
                        var title: String { "surface" }
                        static func make() -> Self { .ready }
                    }
                    struct Details: Sendable {
                        let title: String
                        init(title: String) { self.title = title }
                    }
                    var surfaceIdentity: SurfaceIdentity { .ready }
                }
                extension GenericOwner.Phase.SurfaceIdentity {
                    enum Nested: Sendable { case idle }
                }
                extension GenericOwner where Launch == Int {
                    enum Concrete { case ready }
                }
                """),
            ],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        #expect(module.declarations.count(where: { $0.kind != .enumerationInspection }) == 19)
        #expect(module.declarations.count(where: { $0.kind == .enumerationInspection }) == 4)
        for declaration in module.declarations {
            let binding = planner.plan(declaration)
            #expect(binding.unsupportedReason != nil)
            if declaration.file == "Extension.swift",
               declaration.owner?.hasPrefix("GenericOwner.Phase") == true ||
               declaration.kind == .typeExtension && declaration.name
               .hasPrefix("GenericOwner.Phase")
            {
                #expect(binding.unsupportedReason?.contains("concrete specialization") == true)
            }
        }
        for name in [
            "GenericOwner.Phase.SurfaceIdentity",
            "GenericOwner.Phase.SurfaceIdentity.Nested",
            "GenericOwner.Phase.Details",
        ] {
            #expect(!planner.isSendable(name, relativeTo: nil))
            #expect(!planner.isTransferable(name, relativeTo: nil, onMainActor: true))
        }
        let generated = try BindingEmitter(planner: planner).emit()
        #expect(generated.contains("GenericOwner.Phase.SurfaceIdentity.splash"))
        #expect(!generated.contains("fileprivate static func invoke"))
        #expect(!generated.contains("let result:"))
    }

    @Test func enumConstructorsUseValuesOrMainActorBoxesWithoutAReceiver() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            enum Value: Sendable { case idle, count(Int) }
            enum Plain {
                case idle, count(Int)
                var number: Int { 1 }
                func read() -> Int { 1 }
                nonisolated func delayed() async -> Int { 1 }
            }
            @MainActor protocol Observer: AnyObject {}
            enum Watching { case active(any Observer) }
            enum Unsafe { case pointer(UnsafeRawPointer), callback(() -> Void) }
            struct Resource: ~Copyable {}
            enum Noncopyable: ~Copyable { case owned(Resource) }
            enum Generic<T> { case generic(T) }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        for declaration in module.declarations where declaration.kind == .enumerationCase {
            let binding = planner.plan(declaration)
            #expect(binding.receiverType == nil)
            switch declaration.owner {
                case "Value":
                    #expect(binding.unsupportedReason == nil)
                    #expect(!binding.isMainActor)
                case "Plain", "Watching":
                    #expect(binding.unsupportedReason == nil)
                    #expect(binding.isMainActor)
                    #expect(!planner.isSendable(declaration.resultType ?? "", relativeTo: nil))
                case "Unsafe":
                    #expect(binding.unsupportedReason != nil)
                    if declaration.name == "pointer" {
                        #expect(binding.unsupportedReason?.contains("UnsafeRawPointer") == true)
                    }
                case "Noncopyable":
                    #expect(binding.unsupportedReason?.contains("Noncopyable") == true)
                case "Generic":
                    #expect(binding.unsupportedReason?.contains("specialization") == true)
                case .none, .some:
                    Issue.record("Unexpected enum owner")
            }
        }
        for declaration in module.declarations where declaration.owner == "Plain" &&
            ["number", "read"].contains(declaration.name)
        {
            let binding = planner.plan(declaration)
            #expect(binding.isMainActor)
            #expect(binding.unsupportedReason == nil)
        }
        let delayed = try #require(module.declarations.first { $0.name == "delayed" })
        #expect(!planner.plan(delayed).isMainActor)
        #expect(planner.plan(delayed).unsupportedReason?.contains("receiver") == true)
    }

    @Test func extendingSDKViewDoesNotShadowItsActorIsolation() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            import SwiftUI
            extension View { func helper() -> Int { 1 } }
            struct Screen: View {
                static let maxRows: Int = 3
                static func paletteIndex() -> Int { 2 }
            }
            extension Screen { static var addPrefill: Int { 1 } }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        for declaration in module.declarations where
            ["maxRows", "paletteIndex", "addPrefill"].contains(declaration.name)
        {
            let binding = planner.plan(declaration)
            #expect(binding.isMainActor)
            #expect(binding.unsupportedReason == nil)
        }
    }

    @Test func nestedValuesUseActorBoxesWithoutAssumingSendability() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            @MainActor final class Model {
                enum State { case idle }
                struct Details {
                    let title: String
                    init(title: String) { self.title = title }
                    func name() -> String { title }
                    func delayed() async -> String { title }
                }
                var state: State = .idle
                var details: Details = Details(title: "before")
            }
            struct Detached {}
            struct Resource: ~Copyable {}
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        #expect(!planner.isSendable("Model.State", relativeTo: nil))
        #expect(!planner.isSendable("Model.Details", relativeTo: nil))
        #expect(planner.isTransferable("[Details?]", relativeTo: "Model", onMainActor: true))
        #expect(!planner.isTransferable("Model.Details", relativeTo: nil, onMainActor: false))
        #expect(planner.isTransferable("Detached", relativeTo: nil, onMainActor: true))
        #expect(!planner.isTransferable("Resource", relativeTo: nil, onMainActor: true))
        for declaration in module.declarations where
            (["state", "details"].contains(declaration.name) && declaration.owner == "Model") ||
            (declaration.owner == "Model.Details" && ["title", "init", "name"]
                .contains(declaration.name))
        {
            let binding = planner.plan(declaration)
            #expect(binding.isMainActor)
            #expect(binding.unsupportedReason == nil)
        }
        let delayed = try #require(module.declarations.first { $0.name == "delayed" })
        #expect(!planner.plan(delayed).isMainActor)
        #expect(planner.plan(delayed).unsupportedReason != nil)
        let generated = try BindingEmitter(planner: planner).emit()
        #expect(generated.contains("as: PortholeMainActorValue<Model.State>.self"))
        #expect(generated.contains("as: PortholeMainActorValue<Model.Details>.self"))
    }

    @Test func viewAndSourceConformancesInferMemberIsolation() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            import SwiftUI
            struct Screen: View {
                static let maxRows: Int = 3
                static func paletteIndex() -> Int { 2 }
                nonisolated static func identifier() -> String { "screen" }
            }
            extension Screen { static var addPrefill: Int { 1 } }
            @MainActor protocol Presenter {}
            protocol ChildPresenter: Presenter {}
            class Model: ChildPresenter { static var title: String { "model" } }
            class ChildModel: Model { static var subtitle: String { "child" } }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        for declaration in module.declarations where
            ["maxRows", "paletteIndex", "addPrefill", "title", "subtitle"]
            .contains(declaration.name)
        {
            let binding = planner.plan(declaration)
            #expect(binding.isMainActor)
            #expect(binding.unsupportedReason == nil)
        }
        let identifier = try #require(module.declarations.first { $0.name == "identifier" })
        #expect(!planner.plan(identifier).isMainActor)
        #expect(!planner.isSendable("Screen", relativeTo: nil))
    }

    @Test func localViewNameAndIsolatedExtensionsDoNotIsolateUnrelatedMembers() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            protocol View {}
            struct Plain: View { static let count: Int = 1 }
            @MainActor extension Plain { static var isolated: Int { 2 } }
            struct Qualified: SwiftUI.View { static let count: Int = 3 }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        let plain = try #require(module.declarations
            .first { $0.name == "count" && $0.owner == "Plain" })
        let isolated = try #require(module.declarations.first { $0.name == "isolated" })
        let qualified = try #require(module.declarations
            .first { $0.name == "count" && $0.owner == "Qualified" })
        #expect(!planner.plan(plain).isMainActor)
        #expect(planner.plan(isolated).isMainActor)
        #expect(planner.plan(qualified).isMainActor)
        #expect(!planner.isSendable("Plain", relativeTo: nil))
    }

    @Test func storedValuesWithApplicationEncodersRequireApproval() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            struct Encoded: Sendable, Encodable { func encode(to encoder: any Encoder) throws {} }
            struct Held: Sendable { let count: Int }
            actor Model {
                let custom: Encoded = Encoded()
                let values: [Encoded] = []
                let primitive: [Int] = []
                let held: Held = Held(count: 2)
            }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        for name in ["custom", "values"] {
            let declaration = try #require(module.declarations
                .first { $0.owner == "Model" && $0.name == name })
            #expect(!planner.hasKnownStoredGetter(declaration))
            #expect(planner.resultSerializationRequiresApproval(declaration))
        }
        for name in ["primitive", "held"] {
            let declaration = try #require(module.declarations
                .first { $0.owner == "Model" && $0.name == name })
            #expect(planner.hasKnownStoredGetter(declaration))
        }
        let generated = try BindingEmitter(planner: planner).emit()
        #expect(generated
            .contains(
                "Result serialization can execute application Encodable code and requires approval.",
            ))
    }

    @Test func mainActorProtocolExistentialsUseActorOwnedTransfer() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: """
            @MainActor protocol Observer: AnyObject { func read() -> Int }
            @MainActor final class Model { var observers: [any Observer] = [] }
            func unisolated(_ observer: any Observer) {}
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        #expect(!planner.isSendable("any Observer", relativeTo: nil))
        #expect(planner.isTransferable("[any Observer]", relativeTo: nil, onMainActor: true))
        #expect(!planner.isTransferable("[any Observer]", relativeTo: nil, onMainActor: false))
        let read = try #require(module.declarations.first { $0.name == "read" })
        #expect(planner.plan(read).receiverType == "any Observer")
        #expect(planner.plan(read).unsupportedReason == nil)
        let unisolated = try #require(module.declarations.first { $0.name == "unisolated" })
        #expect(planner.plan(unisolated).unsupportedReason != nil)
    }

    @Test func onlyOrdinaryStoredGettersHaveKnownReadEffects() throws {
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [.init(
            path: "Fixture.swift",
            content: """
            @Observable @MainActor final class Model { var count: Int = 0 }
            actor Engine {
                private let count: Int = 0
                lazy var expensive: Int = 0
                static let shared: Int = 0
            }
            let global: Int = 0
            """,
        )])
        let planner = BindingPlanner(module: module, dependencyModules: [])
        let knownReads = module.declarations.filter(planner.hasKnownStoredGetter)
        #expect(knownReads.count == 1)
        #expect(knownReads.first?.owner == "Engine")
        #expect(knownReads.first?.name == "count")
    }

    @Test func nonisolatedMembersDoNotInheritActorOwnership() throws {
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [SourceFile(
            path: "Fixture.swift",
            content: """
            actor Engine { nonisolated func name() -> String { "engine" } }
            @MainActor final class Model { nonisolated func value() -> Int { 3 } }
            """,
        )])
        let planner = BindingPlanner(module: module, dependencyModules: [])
        for declaration in module.declarations.filter({ $0.kind == .function }) {
            let binding = planner.plan(declaration)
            #expect(declaration.isNonisolated)
            #expect(!binding.isMainActor)
            #expect(!binding.isActor)
            #expect(binding.unsupportedReason == nil)
        }
    }

    @Test func respectsIsolationAndUnsupportedSignatures() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [SourceFile(path: "Fixture.swift", content: """
            actor Engine {
                private var count: Int = 0
                func advance(by amount: Int) async throws -> Int { amount }
                func callback(_ body: () -> Int) -> Int { body() }
                func generic<T>(_ value: T) -> T { value }
            }
            final class Unsafe {
                var count: Int = 0
            }
            struct Value: Sendable { var count: Int }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [])
        let bindings = module.declarations.map(planner.plan)
        #expect(bindings.first { $0.declaration.name == "advance" }?.unsupportedReason == nil)
        #expect(bindings.first { $0.declaration.name == "callback" }?.unsupportedReason?
            .contains("Closure") == true)
        #expect(bindings.first { $0.declaration.name == "generic" }?.unsupportedReason?
            .contains("Generic") == true)
        #expect(bindings.first { $0.declaration.owner == "Unsafe" }?.unsupportedReason?
            .contains("receiver") == true)
        #expect(bindings
            .first { $0.declaration.owner == "Engine" && $0.declaration.kind == .propertySetter }?
            .unsupportedReason == nil)
        #expect(bindings
            .first { $0.declaration.owner == "Value" && $0.declaration.kind == .propertySetter }?
            .unsupportedReason?.contains("write-back") == true)
    }

    @Test func resolvesDependencySendabilityAndMainActorOwnership() throws {
        let dependency = try SourceScanner().scan(
            moduleName: "Dependency",
            files: [SourceFile(path: "Value.swift", content: "struct Value: Sendable {}")],
        )
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [SourceFile(path: "Fixture.swift", content: """
            @MainActor final class Model {
                private var count: Int = 0
                func value() -> Value { Value() }
            }
            """)],
        )
        let planner = BindingPlanner(module: module, dependencyModules: [dependency])
        let method = try #require(module.declarations.first { $0.name == "value" })
        let binding = planner.plan(method)
        #expect(binding.isMainActor)
        #expect(binding.unsupportedReason == nil)
        #expect(planner.isSendable("[Value?]", relativeTo: nil))
    }
}
