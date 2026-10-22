import SnapshotReviewCore
import Testing

struct SnapshotVariantTests {
    @Test func regularAndCombinedVariants() {
        #expect(SnapshotVariant.light.appearance == .light)
        #expect(SnapshotVariant.dark.appearance == .dark)
        var combined = SnapshotVariant.dark
        combined.bold = true
        combined.accessibility = true
        #expect(combined.appearance == .other)
        #expect(combined.label.contains("Bold"))
        #expect(combined.label.contains("VoiceOver"))
    }
}
