@_spi(Testing) import PeriscopeCore
import Testing

struct NetworkPathChangeFilterTests {
    @Test func emitsTheFirstDescription() {
        let filter = NetworkPathChangeFilter()

        let event = filter.event(for: "satisfied (wifi)")

        #expect(event?.kind == .network)
        #expect(event?.value == "satisfied (wifi)")
    }

    @Test func dropsRepeatedIdenticalDescriptions() {
        let filter = NetworkPathChangeFilter()

        _ = filter.event(for: "satisfied (wifi)")

        #expect(filter.event(for: "satisfied (wifi)") == nil)
        #expect(filter.event(for: "satisfied (wifi)") == nil)
    }

    @Test func emitsWhenTheDescriptionChanges() {
        let filter = NetworkPathChangeFilter()

        _ = filter.event(for: "satisfied (wifi)")

        #expect(filter.event(for: "unsatisfied")?.value == "unsatisfied")
    }

    @Test func emitsAValueThatRecursAfterADifferentOne() {
        // Only *consecutive* duplicates are dropped — genuine flapping
        // (wifi → cellular → wifi) must still be logged.
        let filter = NetworkPathChangeFilter()

        _ = filter.event(for: "satisfied (wifi)")
        _ = filter.event(for: "satisfied (cellular)")

        #expect(filter.event(for: "satisfied (wifi)")?.value == "satisfied (wifi)")
    }

    @Test func reemitsTheNextDescriptionAfterReset() {
        let filter = NetworkPathChangeFilter()

        _ = filter.event(for: "satisfied (wifi)")
        filter.reset()

        #expect(filter.event(for: "satisfied (wifi)")?.value == "satisfied (wifi)")
    }
}
