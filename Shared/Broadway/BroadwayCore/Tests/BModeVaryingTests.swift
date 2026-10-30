import BroadwayCore
import Testing

struct BModeVaryingTests {
    @Test func selectsExplicitMode() {
        let values = BModeVarying(light: 12, dark: 24)
        #expect(values[.light] == 12)
        #expect(values[.dark] == 24)
    }

    @Test func supportsConditionalValueConformances() {
        let first = BModeVarying(light: 1, dark: 2)
        let same = BModeVarying(light: 1, dark: 2)
        let different = BModeVarying(light: 1, dark: 3)
        #expect(first == same)
        #expect(first != different)
        #expect(Set([first, same, different]).count == 2)
        func requiresSendable(_: some Sendable) {}
        requiresSendable(first)
    }

    @Test func acceptsValuesWithoutEquatableConformance() {
        let values = BModeVarying(light: { 1 }, dark: { 2 })
        #expect(values[.light]() == 1)
        #expect(values[.dark]() == 2)
    }
}
