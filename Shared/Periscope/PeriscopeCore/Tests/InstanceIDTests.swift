import Foundation
import PeriscopeCore
import Testing

private final class FirstFixture {}
private final class SecondFixture {}

struct InstanceIDTests {
    @Test func sameInstanceYieldsEqualIDs() {
        let object = FirstFixture()
        #expect(InstanceID(of: object) == InstanceID(of: object))
        #expect(InstanceID(of: object).hashValue == InstanceID(of: object).hashValue)
    }

    @Test func distinctLiveInstancesYieldDistinctIDs() {
        // Both must stay alive for the comparison: a released temporary's
        // address gets recycled immediately (the exact phenomenon the
        // dealloc trackers guard against).
        let first = FirstFixture()
        let second = FirstFixture()
        #expect(InstanceID(of: first) != InstanceID(of: second))
        withExtendedLifetime(first) {}
        withExtendedLifetime(second) {}
    }

    @Test func debugDescriptionNamesTheType() {
        let id = InstanceID(of: FirstFixture())
        #expect(id.debugDescription.hasPrefix("FirstFixture@0x"))
        #expect(id.typeName == "FirstFixture")
    }

    @Test func worksAsADictionaryKey() {
        let first = FirstFixture()
        let second = SecondFixture()
        var counts: [InstanceID: Int] = [:]
        counts[InstanceID(of: first)] = 1
        counts[InstanceID(of: second)] = 2

        #expect(counts[InstanceID(of: first)] == 1)
        #expect(counts[InstanceID(of: second)] == 2)
        #expect(counts.count == 2)
    }
}
