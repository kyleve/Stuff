import Foundation
import PeriscopeCore
import Testing

struct LogExportControlTests {
    @Test func consumerControlsHaveStableValueIdentity() {
        #expect(LogExportControl
            .customerDiagnostics == LogExportControl("example.customer-diagnostics"))
        #expect(LogExportControl.customerDiagnostics != .futureControl)
        #expect(Set([LogExportControl.customerDiagnostics, .customerDiagnostics]).count == 1)
    }

    @Test func controlEncodesAsBareIdentifier() throws {
        let data = try JSONEncoder().encode(LogExportControl.customerDiagnostics)
        #expect(String(decoding: data, as: UTF8.self) == "\"example.customer-diagnostics\"")
        #expect(try JSONDecoder().decode(LogExportControl.self, from: data) == .customerDiagnostics)
    }

    @Test func unknownIdentifierRoundTripsWithoutRegistration() throws {
        let data = Data("\"another-framework.new-control\"".utf8)
        let control = try JSONDecoder().decode(LogExportControl.self, from: data)
        #expect(try JSONEncoder().encode(control) == data)
        #expect(LogExportPolicy(mode: .diagnostic, enabledControls: [])[control] == false)
    }

    @Test func emptyIdentifierIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LogExportControl.self, from: Data("\"\"".utf8))
        }
    }

    @Test func builtInIdentitiesAreDistinct() {
        let controls: Set<LogExportControl> = [.identifiers, .location, .userContent, .personalData]
        #expect(controls.count == 4)
        #expect(controls.map(\.rawValue).allSatisfy { $0.hasPrefix("periscope.") })
    }
}
