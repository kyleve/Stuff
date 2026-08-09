import CoreGraphics
import PatchlightCore
@_spi(Testing) import PatchlightUI
import Testing

@MainActor
struct PatchlightDiffCollectionViewTests {
    @Test func twentyThousandLineFixtureCreatesOnlyViewportCells() {
        let lines = (1 ... 20000).map { line in
            DiffLine(
                id: DiffLine.ID(rawValue: "line:\(line)"),
                kind: .context,
                oldLine: line,
                newLine: line,
                text: "let value\(line) = \(line)",
            )
        }
        let file = DiffFile(
            path: "Sources/Large.swift",
            previousPath: nil,
            status: .modified,
            additions: 0,
            deletions: 0,
            baseBlobOID: nil,
            headBlobOID: nil,
            availability: .complete,
            hunks: [DiffHunk(
                id: DiffHunk.ID(rawValue: "large:0"),
                header: "@@ -1,20000 +1,20000 @@",
                oldStart: 1,
                oldCount: 20000,
                newStart: 1,
                newCount: 20000,
                lines: lines,
            )],
        )

        let measurement = PatchlightDiffRendererTesting.measureInitialViewport(
            file: file,
            mode: .unified,
            viewport: CGSize(width: 1024, height: 768),
        )

        #expect(measurement.rowCount == 20001)
        #expect(measurement.configuredCellCount > 0)
        #expect(measurement.configuredCellCount < 100)
    }
}
