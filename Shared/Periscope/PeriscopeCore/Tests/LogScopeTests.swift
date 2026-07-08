import Foundation
import PeriscopeCore
import Testing

struct LogScopeTests {
    @Test func rootHasNoParent() {
        let root = LogScope.root(named: "photos")
        #expect(root.name == "photos")
        #expect(root.parentID == nil)
    }

    @Test func childKeepsItsParentChain() {
        let root = LogScope.root(named: "photos")
        let album = root.child(named: "album-1")
        let photo = album.child(named: "photo-9")
        #expect(album.parentID == root.id)
        #expect(photo.parentID == album.id)
        #expect(photo.name == "photo-9")
    }

    @Test func roundTripsThroughCodable() throws {
        let scope = LogScope.root(named: "photos").child(named: "album-1")
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(LogScope.self, from: data)
        #expect(decoded == scope)
    }
}
