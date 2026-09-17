import Testing
@testable import WhereCore

struct DayBoundsTests {
    @Test func unequalEndpointsRoundOutwardWithoutLosingDateUncertainty() {
        #expect(DayBounds.rounded(lowerNumerator: 455, upperNumerator: 488, denominator: 4)
            == DayBounds(lower: 113, upper: 122))
        #expect(DayBounds.rounded(lowerNumerator: 743, upperNumerator: 745, denominator: 4)
            == DayBounds(lower: 185, upper: 187))
    }

    @Test func equalEndpointsKeepOneNearestRoundedEstimate() {
        let oddDenominator = DayBounds.rounded(lowerNumerator: 5, upperNumerator: 5, denominator: 3)
        #expect(oddDenominator == DayBounds(exact: 2))
        #expect(oddDenominator.isExact)
        #expect(DayBounds.rounded(lowerNumerator: 5, upperNumerator: 5, denominator: 2)
            == DayBounds(exact: 3))
    }
}
