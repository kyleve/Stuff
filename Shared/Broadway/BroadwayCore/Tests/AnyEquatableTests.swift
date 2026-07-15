@testable import BroadwayCore
import Testing

struct AnyEquatableTests {
    // MARK: - Initialization

    @Test("Stores the wrapped value")
    func storesValue() {
        let wrapped = AnyEquatable(42)
        #expect(wrapped.base as? Int == 42)
    }

    @Test("Stores a string value")
    func storesString() {
        let wrapped = AnyEquatable("hello")
        #expect(wrapped.base as? String == "hello")
    }

    // MARK: - Equality (Same Type)

    @Test("Equal values of the same type are equal")
    func sameTypeEqualValues() {
        let a = AnyEquatable(42)
        let b = AnyEquatable(42)
        #expect(a == b)
    }

    @Test("Different values of the same type are not equal")
    func sameTypeDifferentValues() {
        let a = AnyEquatable(1)
        let b = AnyEquatable(2)
        #expect(a != b)
    }

    @Test("Equal string values are equal")
    func equalStrings() {
        let a = AnyEquatable("hello")
        let b = AnyEquatable("hello")
        #expect(a == b)
    }

    // MARK: - Equality (Different Types)

    @Test("Different types are not equal, even with similar values")
    func differentTypesNotEqual() {
        let intValue = AnyEquatable(1)
        let doubleValue = AnyEquatable(1.0)
        #expect(intValue != doubleValue)
    }

    @Test("Int and String are not equal")
    func intAndStringNotEqual() {
        let a = AnyEquatable(42)
        let b = AnyEquatable("42")
        #expect(a != b)
    }

    // MARK: - Symmetry

    @Test("Equality is symmetric for matching types")
    func symmetricEqual() {
        let a = AnyEquatable(10)
        let b = AnyEquatable(10)
        #expect(a == b)
        #expect(b == a)
    }

    @Test("Inequality is symmetric for different types")
    func symmetricNotEqual() {
        let a = AnyEquatable(10)
        let b = AnyEquatable("10")
        #expect(a != b)
        #expect(b != a)
    }

    // MARK: - Complex Types

    @Test("Works with arrays")
    func arrayValues() {
        let a = AnyEquatable([1, 2, 3])
        let b = AnyEquatable([1, 2, 3])
        let c = AnyEquatable([4, 5, 6])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Works with optionals")
    func optionalValues() {
        let a = AnyEquatable(Int?.none)
        let b = AnyEquatable(Int?.none)
        let c = AnyEquatable(Int?.some(42))
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Works with custom Equatable structs")
    func customStruct() {
        struct Point: Equatable {
            var x: Int
            var y: Int
        }

        let a = AnyEquatable(Point(x: 1, y: 2))
        let b = AnyEquatable(Point(x: 1, y: 2))
        let c = AnyEquatable(Point(x: 3, y: 4))
        #expect(a == b)
        #expect(a != c)
    }
}
