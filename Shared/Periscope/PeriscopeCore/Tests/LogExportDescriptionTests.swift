import Foundation
import PeriscopeCore
import Testing

struct LogExportDescriptionTests {
    @Test func deniedParentDoesNotEncodeAnIncompatibleCategory() throws {
        let value = ProjectionTestLog.Object(category: .shared(.category, .init(rawValue: "ready")))
        let description = LogExportDescription.object([
            LogExportField(.init("event"), value: value, requirements: .never),
        ])
        let metadata = LogExportMetadata(payload: description.schema)
        #expect(try JSONEncoder().encode(metadata).isEmpty == false)
        #expect(try description.exportedValue(using: .init(
            mode: .diagnostic,
            enabledControls: [.personalData],
        )) == .object([:]))
    }

    @Test func metadataCaptureDoesNotEncodeDeniedValues() throws {
        let description = LogExportDescription.object([
            LogExportField(.init("secret"), value: JSONValue.double(.nan), requirements: .never),
        ])
        let data = try JSONEncoder().encode(LogExportMetadata(payload: description.schema))
        #expect(data.isEmpty == false)
        #expect(try description.exportedValue(using: .init(
            mode: .diagnostic,
            enabledControls: [.personalData],
        )) == .object([:]))
    }
}
