import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct PlainTextExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        [.plainText]
    }

    public let text: String

    public init(text: String) {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
