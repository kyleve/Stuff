import Testing
@_spi(CopyOnWrite) @testable import BroadwayCore

struct CopyOnWriteTests {
    // MARK: - Initialization

    @Test("Stores the initial value")
    func initialization() {
        let cow = CopyOnWrite(wrappedValue: 42)
        #expect(cow.wrappedValue == 42)
    }

    // MARK: - Copy-on-Write Semantics

    @Test("Copying shares storage until mutation")
    func copySharesStorage() {
        let a = CopyOnWrite(wrappedValue: [1, 2, 3])
        var b = a

        // Both should read the same value.
        #expect(a.wrappedValue == [1, 2, 3])
        #expect(b.wrappedValue == [1, 2, 3])

        // Mutating `b` should not affect `a`.
        b.wrappedValue = [4, 5, 6]
        #expect(a.wrappedValue == [1, 2, 3])
        #expect(b.wrappedValue == [4, 5, 6])
    }

    @Test("Mutating original does not affect copy")
    func mutatingOriginalDoesNotAffectCopy() {
        var a = CopyOnWrite(wrappedValue: "hello")
        let b = a

        a.wrappedValue = "world"
        #expect(a.wrappedValue == "world")
        #expect(b.wrappedValue == "hello")
    }

    @Test("Multiple copies are independent")
    func multipleCopiesAreIndependent() {
        let original = CopyOnWrite(wrappedValue: 10)
        var copy1 = original
        var copy2 = original

        copy1.wrappedValue = 20
        copy2.wrappedValue = 30

        #expect(original.wrappedValue == 10)
        #expect(copy1.wrappedValue == 20)
        #expect(copy2.wrappedValue == 30)
    }

    @Test("Unique reference mutates in place")
    func uniqueReferenceMutatesInPlace() {
        var cow = CopyOnWrite(wrappedValue: [1, 2, 3])

        // With a single owner, mutation should work and the value should update.
        cow.wrappedValue.append(4)
        #expect(cow.wrappedValue == [1, 2, 3, 4])
    }

    // MARK: - Unsafe Underlying Value

    @Test("Unsafe access reads the current value")
    func unsafeRead() {
        let cow = CopyOnWrite(wrappedValue: "test")
        #expect(cow._unsafeUnderlyingValue == "test")
    }

    @Test("Unsafe mutation bypasses copy-on-write")
    func unsafeMutationBypassesCOW() {
        let a = CopyOnWrite(wrappedValue: [1, 2, 3])
        let b = a

        // Unsafe mutation on `b` should also affect `a`
        // since they share the same box.
        b._unsafeUnderlyingValue = [99]

        #expect(a.wrappedValue == [99])
        #expect(b.wrappedValue == [99])
    }

    // MARK: - Equatable

    @Test("Equal values are equal")
    func equalValues() {
        let a = CopyOnWrite(wrappedValue: 42)
        let b = CopyOnWrite(wrappedValue: 42)
        #expect(a == b)
    }

    @Test("Different values are not equal")
    func differentValues() {
        let a = CopyOnWrite(wrappedValue: 1)
        let b = CopyOnWrite(wrappedValue: 2)
        #expect(a != b)
    }

    @Test("Copies are equal")
    func copiesAreEqual() {
        let a = CopyOnWrite(wrappedValue: "hello")
        let b = a
        #expect(a == b)
    }

    @Test("Mutated copy is no longer equal")
    func mutatedCopyIsNotEqual() {
        let a = CopyOnWrite(wrappedValue: [1, 2, 3])
        var b = a

        b.wrappedValue = [4, 5, 6]
        #expect(a != b)
    }

    // MARK: - Property Wrapper

    @Test("Works as a property wrapper")
    func propertyWrapper() {
        struct Model {
            @CopyOnWrite var data: [Int]
        }

        var model = Model(data: [1, 2, 3])
        #expect(model.data == [1, 2, 3])

        model.data = [4, 5, 6]
        #expect(model.data == [4, 5, 6])
    }

    @Test("Property wrapper preserves copy-on-write semantics")
    func propertyWrapperCOW() {
        struct Model: Equatable {
            @CopyOnWrite var data: [Int]
        }

        let a = Model(data: [1, 2, 3])
        var b = a

        b.data.append(4)
        #expect(a.data == [1, 2, 3])
        #expect(b.data == [1, 2, 3, 4])
    }

    // MARK: - Hashable

    @Test("Equal values produce the same hash")
    func hashableConsistency() {
        let a = CopyOnWrite(wrappedValue: 42)
        let b = CopyOnWrite(wrappedValue: 42)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Can be used as a dictionary key")
    func usableAsDictionaryKey() {
        let key = CopyOnWrite(wrappedValue: "key")
        let dict = [key: "value"]
        #expect(dict[key] == "value")
    }

    // MARK: - Edge Cases

    @Test("Works with an empty collection")
    func emptyCollection() {
        let cow = CopyOnWrite<[Int]>(wrappedValue: [])
        #expect(cow.wrappedValue.isEmpty)
    }

    @Test("Works with optional values")
    func optionalValue() {
        var cow = CopyOnWrite<String?>(wrappedValue: nil)
        #expect(cow.wrappedValue == nil)

        cow.wrappedValue = "value"
        #expect(cow.wrappedValue == "value")
    }
}
