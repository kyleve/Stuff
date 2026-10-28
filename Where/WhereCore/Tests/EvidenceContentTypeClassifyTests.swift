import Foundation
import Testing
import UniformTypeIdentifiers
@testable import WhereCore

struct EvidenceContentTypeClassifyTests {
    @Test func typeIdentifier_pdf_winsOverBytes() {
        // Declared PDF is honored even with empty bytes.
        let result = EvidenceContentType.classify(
            data: Data(),
            typeIdentifier: UTType.pdf.identifier,
        )
        #expect(result == .pdf)
    }

    @Test func typeIdentifier_image_family() {
        let result = EvidenceContentType.classify(
            data: Data(),
            typeIdentifier: UTType.png.identifier,
        )
        #expect(result == .image)
    }

    @Test func typeIdentifier_plainText_family() {
        let result = EvidenceContentType.classify(
            data: Data(),
            typeIdentifier: UTType.plainText.identifier,
        )
        #expect(result == .plainText)
    }

    @Test func sniffs_pdfMagicBytes() {
        let pdf = Data("%PDF-1.7\n…".utf8)
        #expect(EvidenceContentType.classify(data: pdf, typeIdentifier: nil) == .pdf)
    }

    @Test func sniffs_pngMagicBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(EvidenceContentType.classify(data: png, typeIdentifier: nil) == .image)
    }

    @Test func sniffs_jpegMagicBytes() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        #expect(EvidenceContentType.classify(data: jpeg, typeIdentifier: nil) == .image)
    }

    @Test func sniffs_heicFtypBox() {
        // 4-byte box size, then "ftyp", then the "heic" major brand.
        let heic = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
        #expect(EvidenceContentType.classify(data: heic, typeIdentifier: nil) == .image)
    }

    @Test func sniffs_avifFtypBox() {
        // "ftyp" box with the "avif" major brand.
        let avif = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66])
        #expect(EvidenceContentType.classify(data: avif, typeIdentifier: nil) == .image)
    }

    @Test func mp4FtypBox_isNotClassifiedAsImage() {
        // Same ISO-BMFF "ftyp" box, but the "isom" video brand — must not sniff
        // as an image. With no type identifier it falls back to raw data.
        let mp4 = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])
        #expect(EvidenceContentType.classify(data: mp4, typeIdentifier: nil) == .rawData)
    }

    @Test func unknownType_withIdentifier_labelsAsOther() {
        let result = EvidenceContentType.classify(
            data: Data([0x00, 0x01, 0x02, 0x03]),
            typeIdentifier: "com.example.custom",
        )
        #expect(result == .other("com.example.custom"))
    }

    @Test func unknownType_noIdentifier_fallsBackToRawData() {
        let result = EvidenceContentType.classify(
            data: Data([0x00, 0x01, 0x02, 0x03]),
            typeIdentifier: nil,
        )
        #expect(result == .rawData)
    }
}
