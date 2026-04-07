import Foundation

public struct YearExportBundle: Equatable, Sendable {
    public let year: Int
    public let generatedAt: Date
    public let plaintext: String
    public let pdfData: Data

    public init(
        year: Int,
        generatedAt: Date = Date(),
        plaintext: String,
        pdfData: Data,
    ) {
        self.year = year
        self.generatedAt = generatedAt
        self.plaintext = plaintext
        self.pdfData = pdfData
    }

    public var plaintextFilename: String {
        "where-\(year)-report.txt"
    }

    public var pdfFilename: String {
        "where-\(year)-report.pdf"
    }
}
