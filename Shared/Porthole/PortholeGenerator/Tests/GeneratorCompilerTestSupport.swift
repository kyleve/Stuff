import Foundation
import Testing

/// Compiles real generated calls against the repository runtime, including private symbol linkage.
enum GeneratorCompilerTestSupport {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func rejectInvalidIsolation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortholeIsolation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Could not remove isolation fixture: \(error)") }
        }
        let original = directory.appendingPathComponent("Original.swift")
        let caller = directory.appendingPathComponent("Caller.swift")
        try """
        actor Engine { private var count: Int = 0 }
        @MainActor final class Model { private var value: Int = 0 }
        """.write(to: original, atomically: true, encoding: .utf8)
        try """
        func invalidActor(_ engine: Engine) -> Int { engine.count }
        nonisolated func invalidMainActor(_ model: Model) -> Int { model.value }
        """.write(to: caller, atomically: true, encoding: .utf8)
        for languageVersion in ["5", "6"] {
            for optimization in ["-Onone", "-O"] {
                let log = directory
                    .appendingPathComponent("swift\(languageVersion)-\(optimization).log")
                try Data().write(to: log)
                let output = try FileHandle(forWritingTo: log)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = [
                    "swiftc",
                    "-swift-version",
                    languageVersion,
                    "-strict-concurrency=complete",
                    "-warnings-as-errors",
                    "-parse-as-library",
                    "-enable-private-imports",
                    optimization,
                    "-Xfrontend",
                    "-disable-access-control",
                    "-typecheck",
                    "-module-cache-path",
                    directory.appendingPathComponent("cache").path,
                    original.path,
                    caller.path,
                ]
                process.standardOutput = output
                process.standardError = output
                try process.run()
                process.waitUntilExit()
                try output.close()
                let diagnostics = try String(contentsOf: log, encoding: .utf8)
                #expect(
                    process.terminationStatus != 0,
                    "Unsafe access flags allowed invalid actor access",
                )
                #expect(diagnostics.contains("actor-isolated property 'count'"), "\(diagnostics)")
                #expect(diagnostics.contains("actor-isolated property 'value'"), "\(diagnostics)")
                #expect(
                    !diagnostics.contains("inaccessible due to 'private'"),
                    "The test failed on access control instead of isolation",
                )
            }
        }
    }

    static func verify(source: String, generated: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortholeCompiler-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Could not remove compiler fixture: \(error)") }
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func sources(_ module: String) throws -> [String] {
            try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("Shared/Porthole/\(module)/Sources"),
                includingPropertiesForKeys: nil,
            )
            .filter { $0.pathExtension == "swift" }.map(\.path).sorted()
        }
        func run(_ executable: String, _ arguments: [String]) throws {
            let log = directory.appendingPathComponent("output-\(UUID().uuidString).log")
            try Data().write(to: log)
            let output = try FileHandle(forWritingTo: log)
            defer {
                do { try output.close() } catch {
                    Issue.record("Could not close compiler output: \(error)")
                }
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw try Failure(description: String(contentsOf: log, encoding: .utf8))
            }
        }
        let compiler = [
            "swiftc",
            "-parse-as-library",
            "-strict-concurrency=complete",
            "-warnings-as-errors",
            "-module-cache-path",
            directory.appendingPathComponent("cache").path,
        ]
        let runtimeCompiler = compiler + ["-swift-version", "6"]
        try run(
            "/usr/bin/xcrun",
            runtimeCompiler + ["-emit-library", "-emit-module", "-module-name", "PortholeCore"]
                + sources("PortholeCore") + [
                    "-emit-module-path",
                    directory.appendingPathComponent("PortholeCore.swiftmodule").path,
                    "-o",
                    directory.appendingPathComponent("libPortholeCore.dylib").path,
                ],
        )
        try run(
            "/usr/bin/xcrun",
            runtimeCompiler + [
                "-emit-library",
                "-emit-module",
                "-module-name",
                "PortholeRuntime",
                "-I",
                directory.path,
                "-L",
                directory.path,
                "-lPortholeCore",
            ]
                + sources("PortholeRuntime") + [
                    "-emit-module-path",
                    directory.appendingPathComponent("PortholeRuntime.swiftmodule").path,
                    "-o",
                    directory.appendingPathComponent("libPortholeRuntime.dylib").path,
                ],
        )
        let original = directory.appendingPathComponent("Original.swift")
        let binding = directory.appendingPathComponent("Generated.swift")
        let runner = directory.appendingPathComponent("Runner.swift")
        try source.write(to: original, atomically: true, encoding: .utf8)
        try generated.write(to: binding, atomically: true, encoding: .utf8)
        try runnerSource.write(to: runner, atomically: true, encoding: .utf8)
        for languageVersion in ["5", "6"] {
            for optimization in ["-Onone", "-O"] {
                for debugCondition in [false, true] {
                    let common = compiler + (debugCondition ? ["-D", "DEBUG"] : []) + [
                        "-swift-version",
                        languageVersion,
                        optimization,
                        "-module-name",
                        "Fixture",
                        "-I",
                        directory.path,
                    ]
                    try run(
                        "/usr/bin/xcrun",
                        common + [
                            "-typecheck",
                            "-D",
                            "PORTHOLE_ORIGINAL_SOURCE_CHECK",
                            original.path,
                            binding.path,
                        ],
                    )
                    // Xcode supplies one object and index output per source, including generated
                    // files.
                    // Private imports preserve linkage while Xcode retains its ordinary compilation
                    // mode.
                    let inputs = [original, binding, runner]
                    let outputMap = Dictionary(uniqueKeysWithValues: inputs.map { input in
                        let object = input.deletingPathExtension().appendingPathExtension("o")
                        return (input.path, [
                            "object": object.path,
                            "dependencies": input.deletingPathExtension()
                                .appendingPathExtension("d")
                                .path,
                            "index-unit-output-path": "/Fixture.build/\(object.lastPathComponent)",
                        ])
                    })
                    let outputMapURL = directory.appendingPathComponent("output-map.json")
                    try JSONEncoder().encode(outputMap).write(to: outputMapURL)
                    try run(
                        "/usr/bin/xcrun",
                        common + [
                            "-c",
                            "-Xfrontend",
                            "-disable-access-control",
                            "-enable-private-imports",
                            "-enable-batch-mode",
                            "-driver-batch-count",
                            "1",
                            "-emit-dependencies",
                            "-output-file-map",
                            outputMapURL.path,
                            "-index-store-path",
                            directory.appendingPathComponent("index-store").path,
                        ] + inputs.map(\.path),
                    )
                    let objects = inputs
                        .map { $0.deletingPathExtension().appendingPathExtension("o") }
                    for object in objects {
                        #expect(FileManager.default.fileExists(atPath: object.path))
                        #expect(FileManager.default
                            .fileExists(atPath: object.deletingPathExtension()
                                .appendingPathExtension("d")
                                .path))
                    }
                    let executable = directory.appendingPathComponent("fixture")
                    try run(
                        "/usr/bin/xcrun",
                        common + [
                            "-L",
                            directory.path,
                            "-lPortholeCore",
                            "-lPortholeRuntime",
                            "-o",
                            executable.path,
                        ] + objects.map(\.path),
                    )
                    try run(executable.path, [])
                }
            }
        }
    }

    private static let runnerSource = """
    import Foundation
    import PortholeRuntime
    @main enum Runner {
        struct EnumInput {
            let name: String
            let arguments: PortholeValue
            let expected: Int64
        }
        static func main() async throws {
            let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
            let scope = await registry.createScope(id: .init(rawValue: "fixture"))
            await registry.setEnabled(true)
            try await PortholeGeneratedModule.install(in: registry, scope: scope)
            let capabilities = try await registry.capabilities(in: scope)
            precondition(Set(capabilities.map { $0.id }).count == capabilities.count)
            precondition(capabilities.filter { $0.name == "MainActorOnlyObserver.read" }.count == 2)
            precondition(capabilities.filter { $0.name == "Journal" && $0.summary == "extension Journal" }.count == 2)
            let inventory = capabilities.filter { $0.module.rawValue == "InventoryFixture" }
            precondition(inventory.count == 33)
            precondition(inventory.allSatisfy { capability in
                if case .unsupported = capability.availability { return true }
                return false
            })
            precondition(inventory.contains { $0.name == "Credentials.swift" && $0.source == nil })
            let report = try JSONDecoder().decode(PortholeCoverageDocument.self, from: Data(PortholeGeneratedModule.coverageJSON.utf8))
            let coverageModules = try await registry.coverageModules(in: scope, offset: 0, limit: 200)
            precondition(coverageModules.total == 2)
            for module in report.modules {
                let summary = coverageModules.items.first { $0.module == module.module }
                precondition(summary?.counts.total == module.declarations.count)
            }
            let coverage = try await registry.coverage(in: scope, query: .init(module: .init(rawValue: "Fixture"), search: "Coverage", status: .all, offset: 0, limit: 200))
            let debugRow = coverage.items.first { $0.declaration.name == "debugCoverage" }!
            let releaseRow = coverage.items.first { $0.declaration.name == "releaseCoverage" }!
            #if DEBUG
            precondition(debugRow.state == .callable && releaseRow.state == .inactive)
            precondition(debugRow.installedCapabilityID != nil && releaseRow.installedCapabilityID == nil)
            #else
            precondition(debugRow.state == .inactive && releaseRow.state == .callable)
            precondition(debugRow.installedCapabilityID == nil && releaseRow.installedCapabilityID != nil)
            #endif
            precondition(debugRow.declaration.plannedAvailability == .callable && !debugRow.declaration.conditions.isEmpty)
            precondition(debugRow.declaration.sourceSHA256 != nil && releaseRow.declaration.sourceSHA256 != nil)
            let unsupportedRow = coverage.items.first { $0.declaration.name == "unsupportedCoverage" }!
            guard case let .unsupported(reason) = unsupportedRow.state else { fatalError("Missing final planner rejection") }
            precondition(reason.contains("Sendable"))
            let nativeCoverage = try await registry.coverage(in: scope, query: .init(module: .init(rawValue: "InventoryFixture"), search: "", status: .all, offset: 0, limit: 200))
            precondition(nativeCoverage.total == 33)
            precondition(nativeCoverage.items.filter { if case .sourceOnly = $0.state { return true }; return false }.count == 32)
            precondition(nativeCoverage.items.filter { if case .excluded = $0.state { return true }; return false }.count == 1)
            func call(_ name: String, arguments: PortholeValue, receiver: PortholeObjectReference?, signature: String? = nil) async throws -> PortholeValue {
                guard let capability = capabilities.first(where: { $0.name == name && (signature == nil || $0.summary == signature) }) else { fatalError("Missing capability") }
                let invocation = PortholeInvocation(id: UUID(), scope: scope, capabilityID: capability.id, receiver: receiver, arguments: arguments)
                do { return try await registry.invoke(invocation) }
                catch let PortholeError.approvalRequired(proposal) {
                    try await registry.approve(proposal)
                    return try await registry.invoke(invocation)
                }
            }
            func inspect(_ name: String, value: PortholeValue) async throws -> PortholeValue {
                guard let encoded = value["$reference"],
                      let capability = capabilities.first(where: { $0.name == name + ".$inspect" })
                else { fatalError("Missing enum inspection") }
                precondition(capability.effect == .read && capability.parameters.isEmpty)
                let reference = try encoded.decode(PortholeObjectReference.self)
                let result = try await registry.invoke(PortholeInvocation(id: UUID(), scope: scope, capabilityID: capability.id, receiver: reference, arguments: .object([:])))
                try capability.result.validate(result)
                return result
            }
            func payloads(_ inspection: PortholeValue) -> [PortholeValue] {
                guard case let .array(values) = inspection["payloads"] else { fatalError("Missing enum payloads") }
                return values
            }
            let value = try await call("Journal.init", arguments: .object(["count": .integer(7)]), receiver: nil)
            guard let reference = value["$reference"] else { fatalError("Constructor did not retain its result") }
            let receiver = try reference.decode(PortholeObjectReference.self)
            let count = try await call("Journal.count", arguments: .object([:]), receiver: receiver)
            let doubled = try await call("Journal.double", arguments: .object([:]), receiver: receiver)
            precondition(count == .integer(7) && doubled == .integer(14))
            let engine = try await call("Engine.init", arguments: .object(["count": .integer(2)]), receiver: nil)
            guard let engineValue = engine["$reference"] else { fatalError("Missing actor reference") }
            let engineReference = try engineValue.decode(PortholeObjectReference.self)
            _ = try await call("Engine.count.set", arguments: .object(["value": .integer(9)]), receiver: engineReference)
            let updated = try await call("Engine.count", arguments: .object([:]), receiver: engineReference)
            precondition(updated == .integer(9))
            let actorDoubled = try await call("Engine.doubled", arguments: .object([:]), receiver: engineReference, signature: "() -> Int")
            precondition(actorDoubled == .integer(18))
            let editor = try await call("Editor.init", arguments: .object(["count": .integer(3)]), receiver: nil)
            guard let editorValue = editor["$reference"] else { fatalError("Missing editor reference") }
            let editorReference = try editorValue.decode(PortholeObjectReference.self)
            for property in ["state", "details"] {
                let value = try await call("Editor." + property, arguments: .object([:]), receiver: editorReference)
                guard value["$reference"] != nil else { fatalError("Missing boxed nested value") }
                _ = try await call("Editor." + property + ".set", arguments: .object(["value": value]), receiver: editorReference)
            }
            let details = try await call("Editor.Details.init", arguments: .object(["title": .string("changed")]), receiver: nil)
            guard let detailsValue = details["$reference"] else { fatalError("Missing boxed constructed value") }
            let detailsReference = try detailsValue.decode(PortholeObjectReference.self)
            let detailTitle = try await call("Editor.Details.title", arguments: .object([:]), receiver: detailsReference)
            precondition(detailTitle == .string("changed"))
            let loadedState = try await call("Editor.State.loaded", arguments: .object(["argument0": .integer(17)]), receiver: nil)
            precondition(loadedState["$reference"] != nil)
            let loadedInspection = try await inspect("Editor.State", value: loadedState)
            precondition(loadedInspection["case"] == .string("loaded"))
            precondition(payloads(loadedInspection).first?["value"] == .integer(17))
            _ = try await call("Editor.state.set", arguments: .object(["value": loadedState]), receiver: editorReference)
            let stateCount = try await call("Editor.stateCount", arguments: .object([:]), receiver: editorReference)
            precondition(stateCount == .integer(17))
            let idleState = try await call("Editor.State.idle", arguments: .object([:]), receiver: nil)
            _ = try await call("Editor.state.set", arguments: .object(["value": idleState]), receiver: editorReference)
            let view = try await call("InspectorFixtureView.init", arguments: .object([:]), receiver: nil)
            guard view["$reference"] != nil else { fatalError("Missing boxed view") }
            let title = try await call("InspectorFixtureView.title", arguments: .object([:]), receiver: nil)
            let palette = try await call("InspectorFixtureView.paletteIndex", arguments: .object(["for": .string("blue")]), receiver: nil)
            precondition(title == .string("inspector") && palette == .integer(4))
            let holder = try await call("ObserverHolder.init", arguments: .object([:]), receiver: nil)
            guard let holderValue = holder["$reference"] else { fatalError("Missing holder reference") }
            let holderReference = try holderValue.decode(PortholeObjectReference.self)
            let observer = try await call("ObserverHolder.observer", arguments: .object([:]), receiver: holderReference)
            guard let observerValue = observer["$reference"] else { fatalError("Missing boxed observer") }
            let observerReference = try observerValue.decode(PortholeObjectReference.self)
            precondition(observerReference.typeName.contains("ValueObserver") && !observerReference.typeName.contains("PortholeMainActorValue"))
            let observed = try await call("ValueObserver.read", arguments: .object([:]), receiver: observerReference)
            precondition(observed == .integer(11))
            let isolatedObserver = try await call("ObserverHolder.isolatedObserver", arguments: .object([:]), receiver: holderReference)
            let echoedObserver = try await call("ObserverHolder.echo", arguments: .object(["value": isolatedObserver]), receiver: holderReference)
            guard let echoedValue = echoedObserver["$reference"] else { fatalError("Missing echoed MainActor observer") }
            let echoedReference = try echoedValue.decode(PortholeObjectReference.self)
            let isolatedObserved = try await call("MainActorOnlyObserver.read", arguments: .object([:]), receiver: echoedReference)
            precondition(isolatedObserved == .integer(13))
            let watching = try await call("PlainChoice.observer", arguments: .object(["argument0": isolatedObserver]), receiver: nil)
            let watchingCount = try await call("inspectChoice", arguments: .object(["value": watching]), receiver: nil)
            precondition(watchingCount == .integer(13))
            let watchingInspection = try await inspect("PlainChoice", value: watching)
            precondition(watchingInspection["case"] == .string("observer"))
            guard let watchingPayload = payloads(watchingInspection).first?["value"],
                  let watchingObject = watchingPayload["$reference"] else { fatalError("Missing boxed inspection payload") }
            let watchingReference = try watchingObject.decode(PortholeObjectReference.self)
            let watchedCount = try await call("MainActorOnlyObserver.read", arguments: .object([:]), receiver: watchingReference)
            precondition(watchedCount == .integer(13))
            let observers = try await call("ObserverHolder.observers", arguments: .object([:]), receiver: holderReference)
            _ = try await call("ObserverHolder.observers.set", arguments: .object(["value": observers]), receiver: holderReference)
            let cleared = try await call("ObserverHolder.clearObservers", arguments: .object([:]), receiver: holderReference)
            precondition(cleared == .null)
            let character = try await call("character", arguments: .object(["value": .string("é")]), receiver: nil)
            let substring = try await call("substring", arguments: .object(["value": .string("text")]), receiver: nil)
            precondition(character == .string("é") && substring == .string("text"))
            let ignored = try await call("ignored", arguments: .object(["argument0": .integer(3), "argument1": .string("text")]), receiver: nil)
            precondition(ignored == .string("called"))
            let repeated = try await call("repeatLabel", arguments: .object(["first": .integer(3), "second": .string("air"), "for": .string("port")]), receiver: nil)
            precondition(repeated == .string("3airport"))
            let empty = try await call("empty", arguments: .object(["argument0": .null]), receiver: nil)
            precondition(empty == .null)
            do {
                _ = try await call("empty", arguments: .object(["argument0": .integer(1)]), receiver: nil)
                fatalError("Void accepted a non-null argument")
            } catch PortholeError.invalidArguments {}
            let enginesReference = try await registry.retain([Engine(count: 4)], in: scope)
            let engines = try await call("engines", arguments: .object(["values": .object(["$reference": try .encoding(enginesReference)])]), receiver: nil)
            precondition(engines["$reference"] != nil)
            let enumInputs: [EnumInput] = [
                .init(name: "empty", arguments: .object([:]), expected: 0),
                .init(name: "pair", arguments: .object(["argument0": .integer(3), "argument1": .integer(4)]), expected: 7),
                .init(name: "labeled", arguments: .object(["title": .string("air"), "count": .integer(5)]), expected: 8),
                .init(name: "collision", arguments: .object(["argument0_": .integer(4), "argument0": .integer(6)]), expected: 10),
                .init(name: "escaped", arguments: .object(["repeat": .integer(9)]), expected: 9),
                .init(name: "default", arguments: .object([:]), expected: 0),
            ]
            for input in enumInputs {
                let value = try await call("Packet." + input.name, arguments: input.arguments, receiver: nil)
                guard let reference = value["$reference"] else { fatalError("Enum case did not retain a typed result") }
                let receiver = try reference.decode(PortholeObjectReference.self)
                let total = try await call("Packet.total", arguments: .object([:]), receiver: receiver)
                precondition(total == .integer(input.expected))
                let inspection = try await inspect("Packet", value: value)
                precondition(inspection["case"] == .string(input.name))
                for payload in payloads(inspection) {
                    guard let key = payload["name"]?.stringValue else { fatalError("Missing payload key") }
                    precondition(payload["value"] == input.arguments[key])
                }
                if input.name == "empty" { precondition(payloads(inspection).isEmpty) }
                if input.name == "escaped" { precondition(payloads(inspection).first?["label"] == .string("repeat")) }
            }
            let code = try await call("WireCode.ready", arguments: .object([:]), receiver: nil)
            guard let codeValue = code["$reference"] else { fatalError("Encodable enum case invoked its encoder") }
            let codeReference = try codeValue.decode(PortholeObjectReference.self)
            let codeNumber = try await call("WireCode.number", arguments: .object([:]), receiver: codeReference)
            precondition(codeNumber == .integer(7))
            let codeInspection = try await inspect("WireCode", value: code)
            precondition(codeInspection["case"] == .string("ready") && payloads(codeInspection).isEmpty)
            let note = try await call("PlainChoice.note", arguments: .object(["argument0": .string("flight")]), receiver: nil)
            let noteCount = try await call("inspectChoice", arguments: .object(["value": note]), receiver: nil)
            precondition(noteCount == .integer(6))
            guard let noteValue = note["$reference"] else { fatalError("Missing boxed enum value") }
            let noteReference = try noteValue.decode(PortholeObjectReference.self)
            let isNote = try await call("PlainChoice.isNote", arguments: .object([:]), receiver: noteReference)
            precondition(isNote == .bool(true))
            let noteInspection = try await inspect("PlainChoice", value: note)
            precondition(payloads(noteInspection).first?["value"] == .string("flight"))
            let encodedPayload = try await call("EncodedPayload.init", arguments: .object(["title": .string("untouched")]), receiver: nil)
            let opaque = try await call("OpaquePacket.value", arguments: .object(["argument0": encodedPayload]), receiver: nil)
            let opaqueInspection = try await inspect("OpaquePacket", value: opaque)
            guard let opaqueValue = payloads(opaqueInspection).first?["value"],
                  let opaqueObject = opaqueValue["$reference"] else { fatalError("Missing retained Encodable payload") }
            let opaqueReference = try opaqueObject.decode(PortholeObjectReference.self)
            let opaqueTitle = try await call("EncodedPayload.title", arguments: .object([:]), receiver: opaqueReference)
            precondition(opaqueTitle == .string("untouched"))
            let collectionReference = try await registry.retain(OpaquePacket.values([EncodedPayload(title: "array")]), in: scope)
            let collectionInspection = try await inspect("OpaquePacket", value: .object(["$reference": try .encoding(collectionReference)]))
            guard let collectionObject = payloads(collectionInspection).first?["value"]?["$reference"] else { fatalError("Missing typed collection payload") }
            let collectionHandle = try collectionObject.decode(PortholeObjectReference.self)
            let retainedCollection = try await registry.resolve(collectionHandle, as: [EncodedPayload].self, in: scope)
            precondition(retainedCollection.first?.title == "array")
            let exact = try await call("ScalarPacket.exact", arguments: .object(["argument0": .unsignedInteger(UInt64.max), "argument1": .integer(Int64.min)]), receiver: nil)
            let exactInspection = try await inspect("ScalarPacket", value: exact)
            precondition(payloads(exactInspection).map { $0["value"] } == [.unsignedInteger(UInt64.max), .integer(Int64.min)])
            let voidPacket = try await call("ScalarPacket.empty", arguments: .object(["argument0": .null]), receiver: nil)
            let voidInspection = try await inspect("ScalarPacket", value: voidPacket)
            precondition(payloads(voidInspection).first?["value"] == .null)
            let infiniteReference = try await registry.retain(ScalarPacket.number(.infinity), in: scope)
            do {
                _ = try await inspect("ScalarPacket", value: .object(["$reference": try .encoding(infiniteReference)]))
                fatalError("Enum inspection accepted a non-finite number")
            } catch PortholeError.invalidArguments {}
            #if DEBUG
            let conditional = try await call("ConditionalInspection.debug", arguments: .object(["value": .string("debug")]), receiver: nil)
            let expectedConditional = "debug"
            #else
            let conditional = try await call("ConditionalInspection.release", arguments: .object(["value": .integer(4)]), receiver: nil)
            let expectedConditional = "release"
            #endif
            let conditionalInspection = try await inspect("ConditionalInspection", value: conditional)
            precondition(conditionalInspection["case"] == .string(expectedConditional))
            let inspectionCoverage = try await registry.coverage(in: scope, query: .init(module: .init(rawValue: "Fixture"), search: "$inspect", status: .all, offset: 0, limit: 200))
            precondition(inspectionCoverage.items.allSatisfy { $0.declaration.kind == .enumerationInspection })
            precondition(inspectionCoverage.items.first { $0.declaration.name == "Packet.$inspect" }?.state == .callable)
            for name in ["EmptyInspection", "UnsafeInspection", "CallbackInspection", "AvailableInspection", "GenericOwner.Phase"] {
                guard let row = inspectionCoverage.items.first(where: { $0.declaration.name == name + ".$inspect" }),
                      case .unsupported = row.state else { fatalError("Missing inspection restriction") }
            }
            guard let caseCapability = capabilities.first(where: { $0.name == "Packet.empty" }) else { fatalError("Missing enum constructor") }
            precondition(caseCapability.effect == .unknown)
            let unapproved = PortholeInvocation(id: UUID(), scope: scope, capabilityID: caseCapability.id, receiver: nil, arguments: .object([:]))
            do {
                _ = try await registry.invoke(unapproved)
                fatalError("Enum construction bypassed approval")
            } catch PortholeError.approvalRequired {}
            let stale = try await call("Packet.empty", arguments: .object([:]), receiver: nil)
            let staleReference = try stale["$reference"]!.decode(PortholeObjectReference.self)
            let inspectionCapability = capabilities.first { $0.name == "Packet.$inspect" }!
            await registry.invalidate(scope)
            let replacement = await registry.createScope(id: scope.id)
            precondition(replacement != scope)
            do {
                _ = try await registry.invoke(PortholeInvocation(id: UUID(), scope: scope, capabilityID: inspectionCapability.id, receiver: staleReference, arguments: .object([:])))
                fatalError("Enum inspector reused an expired scope")
            } catch PortholeError.staleScope {}
            verifyPrivateValueAndClassMutation()
        }
        @MainActor static func verifyPrivateValueAndClassMutation() {
            var value = CounterValue(count: 3)
            value.count = 4
            value.advance()
            let editor = Editor(count: 1)
            editor.count = value.count
            precondition(editor.count == 5)
        }
    }
    """
}
