import Foundation
import Testing
import UniformTypeIdentifiers
@testable import WhereCore

/// Covers the shared `Evidence.composed` factory and `EvidenceKind` helpers the
/// in-app and share-extension compose forms both build records through.
struct EvidenceCompositionTests {
    private static let captured = Date(timeIntervalSince1970: 1_770_000_000)
    private static let pdfBytes = Data("%PDF-1.7".utf8)

    @Test func composed_classifiesAttachmentAndTrimsNote() {
        let evidence = Evidence.composed(
            kind: .planeTicket,
            otherLabel: "",
            capturedAt: Self.captured,
            note: "  boarding pass  ",
            attachmentData: Self.pdfBytes,
            attachmentTypeIdentifier: nil,
        )
        #expect(evidence.kind == .planeTicket)
        #expect(evidence.contentType == .pdf)
        #expect(evidence.note == "boarding pass")
        #expect(evidence.capturedAt == Self.captured)
        #expect(evidence.region == nil)
    }

    @Test func composed_foldsOtherLabelIntoKind() {
        let evidence = Evidence.composed(
            kind: .other(nil),
            otherLabel: "  Ferry ticket  ",
            capturedAt: Self.captured,
            note: "",
            attachmentData: nil,
            attachmentTypeIdentifier: nil,
        )
        #expect(evidence.kind == .other("Ferry ticket"))
    }

    @Test func composed_emptyOtherLabelDropsLabel() {
        let evidence = Evidence.composed(
            kind: .other(nil),
            otherLabel: "   ",
            capturedAt: Self.captured,
            note: "",
            attachmentData: nil,
            attachmentTypeIdentifier: nil,
        )
        #expect(evidence.kind == .other(nil))
    }

    @Test func composed_withoutAttachmentIsMetadataOnly() {
        let evidence = Evidence.composed(
            kind: .email,
            otherLabel: "",
            capturedAt: Self.captured,
            note: "   ",
            attachmentData: nil,
            attachmentTypeIdentifier: nil,
        )
        #expect(evidence.contentType == .other(nil))
        #expect(evidence.note == nil)
    }

    @Test func suggestedKind_pkpassIsBoardingPass() {
        #expect(EvidenceKind.suggested(forTypeIdentifier: "com.apple.pkpass") == .boardingPass)
    }

    @Test func suggestedKind_imageIsPhoto() {
        #expect(EvidenceKind.suggested(forTypeIdentifier: UTType.png.identifier) == .photo)
    }

    @Test func suggestedKind_pdfIsDocument() {
        #expect(EvidenceKind.suggested(forTypeIdentifier: UTType.pdf.identifier) == .document)
    }

    @Test func suggestedKind_unknownOrNilIsDocument() {
        #expect(EvidenceKind.suggested(forTypeIdentifier: nil) == .document)
        #expect(EvidenceKind.suggested(forTypeIdentifier: "com.example.bogus.type") == .document)
    }
}
