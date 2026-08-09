import PatchlightCore
import Testing

struct UnifiedPatchParserTests {
    @Test func parsesMultipleHunksAndLineNumbers() throws {
        let patch = """
        @@ -1,3 +1,3 @@
         one
        -two
        +second
         three
        @@ -10 +10,2 @@ function
         ten
        +eleven
        """

        let hunks = try UnifiedPatchParser().parse(patch, path: "Sources/File.swift")

        #expect(hunks.count == 2)
        #expect(hunks[0].oldStart == 1)
        #expect(hunks[0].newCount == 3)
        #expect(hunks[0].lines.map(\.kind) == [.context, .deletion, .addition, .context])
        #expect(hunks[0].lines[1].oldLine == 2)
        #expect(hunks[0].lines[2].newLine == 2)
        #expect(hunks[1].newCount == 2)
    }

    @Test func rejectsMalformedContentInsteadOfInventingAnchors() {
        #expect(throws: UnifiedPatchError.invalidHunkHeader) {
            try UnifiedPatchParser().parse("@@ nope @@\n+line", path: "bad")
        }
    }
}
