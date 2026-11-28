import BroadwayCore
import Testing

struct PresentationIdentityTests {
    @Test func openingCreatesAnIdentityThatCopiesRetain() {
        let first = PresentationID<Self>()
        let copy = first
        #expect(copy == first)
        #expect(PresentationID<Self>() != first)
    }

    @Test func successiveEventsChangeTheValueAndPreserveEarlierCopies() {
        var trigger = EventTrigger()
        let initial = trigger
        trigger.fire()
        let first = trigger
        trigger.fire()
        #expect(Set([initial, first, trigger]).count == 3)
    }
}
