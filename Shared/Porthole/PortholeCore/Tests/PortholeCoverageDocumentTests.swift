import Foundation
import PortholeCore
import Testing

struct PortholeCoverageDocumentTests {
    @Test func documentCarriesBuildAndSourceIdentityWithoutSourceContent() throws {
        let declaration = PortholeCoverageTestSupport.declaration()
        let document = PortholeCoverageDocument(version: 1, modules: [.init(
            module: .init(rawValue: "Fixture"),
            build: .init(configuration: "Release", toolchain: "Swift fixture"),
            files: [.init(path: "Fixture.swift", sha256: String(repeating: "a", count: 64))],
            declarations: [declaration],
        )])
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(PortholeCoverageDocument.self, from: data) == document)
        let value = try PortholeValue.encoding(document)
        #expect(value["version"] == .integer(1))
        #expect(!String(decoding: data, as: UTF8.self).contains("\"content\""))
        #expect(document.modules.first?.declarations.first?.plannedAvailability == .callable)
        #expect(document.modules.first?.declarations.first?.conditions == ["DEBUG"])
    }

    @Test func sourceOnlyAndExcludedOriginsRemainExplicitInTheWireDocument() throws {
        let data = Data(#"""
        {"version":1,"modules":[{"module":"Native","build":{"configuration":"Beta","toolchain":"Swift fixture"},"files":[],"declarations":[{"id":"Native:excluded-source:Secrets.swift","name":"Secrets.swift","kind":"excludedFile","signature":"Secrets.swift","conditions":[],"plannedAvailability":{"unsupported":{"_0":"Credential boundary"}},"origin":"excludedFile"}]}]}
        """#.utf8)
        let document = try JSONDecoder().decode(PortholeCoverageDocument.self, from: data)
        let row = try #require(document.modules.first?.declarations.first)
        #expect(document.modules.first?.module.rawValue == "Native")
        #expect(row.id.rawValue == "Native:excluded-source:Secrets.swift")
        #expect(row.kind == .excludedFile)
        #expect(row.origin == .excludedFile)
        #expect(row.source == nil && row.sourceSHA256 == nil)
        #expect(row.plannedAvailability == .unsupported("Credential boundary"))
    }
}
