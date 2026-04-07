import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct PDFExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        [.pdf]
    }

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
