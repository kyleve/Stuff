import RegionKit
import Testing
@testable import WhereUI

@MainActor
struct RegionArtworkModelTests {
    @Test func hidesArtworkImmediatelyWhenDisplayKeyChanges() async {
        let model = RegionArtworkModel<Region, Int>()
        await model.load(for: .ontario) { 1 }
        #expect(model.artwork(for: .ontario) == 1)
        #expect(model.artwork(for: .newYork) == nil)
        await model.load(for: .newYork) {
            #expect(model.artwork(for: .newYork) == nil)
            #expect(model.artwork(for: .ontario) == nil)
            return 2
        }
        #expect(model.artwork(for: .newYork) == 2)
    }

    @Test func retainsCompatibleArtworkUntilRefreshCompletes() async {
        let model = RegionArtworkModel<Region, Int>()
        await model.load(for: .ontario) { 1 }
        await model.load(for: .ontario) {
            #expect(model.artwork(for: .ontario) == 1)
            return 2
        }
        #expect(model.artwork(for: .ontario) == 2)
    }

    @Test(arguments: [Region.ontario, .newYork])
    func supersededLoadCannotReplaceNewerArtwork(newRegion: Region) async {
        let model = RegionArtworkModel<Region, Int>()
        await model.load(for: .ontario) {
            // Reenter while the first operation is suspended, including the
            // same-key case where key comparison alone cannot reject stale work.
            await model.load(for: newRegion) { 2 }
            return 1
        }
        #expect(model.artwork(for: newRegion) == 2)
    }

    @Test func cancelledOperationCannotPublish() async {
        let model = RegionArtworkModel<Region, Int>()
        await model.load(for: .ontario) { 1 }
        let task = Task {
            await model.load(for: .ontario) {
                withUnsafeCurrentTask { $0?.cancel() }
                return 2
            }
        }
        await task.value
        #expect(model.artwork(for: .ontario) == 1)
    }

    @Test func alreadyCancelledTaskDoesNotStartLoading() async {
        let model = RegionArtworkModel<Region, Int>()
        await model.load(for: .ontario) { 1 }
        let task = Task {
            await model.load(for: .newYork) {
                Issue.record("Cancelled task started artwork work")
                return 2
            }
        }
        task.cancel()
        await task.value
        #expect(model.artwork(for: .ontario) == 1)
    }

    @Test func unavailableArtworkClearsPreviousValue() async {
        let model = RegionArtworkModel<Region, Int>()
        await model.load(for: .ontario) { 1 }
        await model.load(for: .ontario) { nil }
        #expect(model.artwork(for: .ontario) == nil)
    }
}
