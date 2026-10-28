import Foundation
import PeriscopeCore
import Testing

struct ScopeIDTests {
    @Test func samePathDerivesTheSameID() {
        let a = LogScope.root(named: "photos").child(named: "album-1")
        let b = LogScope.root(named: "photos").child(named: "album-1")
        #expect(a.id == b.id)
    }

    @Test func differentNamesDeriveDifferentIDs() {
        let root = LogScope.root(named: "photos")
        #expect(root.child(named: "album-1").id != root.child(named: "album-2").id)
    }

    @Test func differentParentsDeriveDifferentIDs() {
        let photos = LogScope.root(named: "photos")
        let videos = LogScope.root(named: "videos")
        #expect(photos.child(named: "item").id != videos.child(named: "item").id)
    }

    @Test func rootAndChildOfSameNameDiffer() {
        let root = LogScope.root(named: "photos")
        #expect(root.id != root.child(named: "photos").id)
    }

    @Test func roundTripsThroughCodable() throws {
        let id = LogScope.root(named: "photos").id
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ScopeID.self, from: data)
        #expect(decoded == id)
    }
}
