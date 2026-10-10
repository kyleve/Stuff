import Foundation
import PeriscopeCore
import Testing

struct LogExportDescriptionTests {
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
