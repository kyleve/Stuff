@testable import BroadwayCore
import Testing

struct TypeIdentifierTests {
    @Test("Same type produces equal identifiers")
    func sameType() {
        let a = TypeIdentifier(Int.self)
        let b = TypeIdentifier(Int.self)
        #expect(a == b)
    }

    @Test("Different types produce unequal identifiers")
    func differentTypes() {
        let a = TypeIdentifier(Int.self)
        let b = TypeIdentifier(String.self)
        #expect(a != b)
    }

    @Test("Equal identifiers have the same hash")
    func hashConsistency() {
        let a = TypeIdentifier(Int.self)
        let b = TypeIdentifier(Int.self)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Can be used as a dictionary key")
    func usableAsDictionaryKey() {
        let key = TypeIdentifier(Int.self)
        let dict = [key: "integer"]
        #expect(dict[key] == "integer")
    }

    @Test("debugDescription returns the type name")
    func debugDescription() {
        let id = TypeIdentifier(String.self)
        #expect(id.debugDescription == "String")
    }

    @Test("Protocols and concrete types are distinct")
    func protocolVsConcrete() {
        let proto = TypeIdentifier((any Equatable).self)
        let concrete = TypeIdentifier(Int.self)
        #expect(proto != concrete)
    }
}
