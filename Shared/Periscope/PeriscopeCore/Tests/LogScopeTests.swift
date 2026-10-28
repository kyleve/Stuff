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

    @Test func ancestryWalksRootFirstThroughTheResolver() {
        let root = LogScope.root(named: "app")
        let photos = root.child(named: "photos")
        let album = photos.child(named: "album-1")
        let known = [root.id: root, photos.id: photos, album.id: album]

        let chain = LogScope.ancestry(of: album.id) { known[$0] }
        #expect(chain == [root, photos, album])
    }

    @Test func ancestryStopsAtTheFirstUnresolvableScope() {
        let root = LogScope.root(named: "app")
        let photos = root.child(named: "photos")
        let known = [photos.id: photos] // parent missing

        #expect(LogScope.ancestry(of: photos.id) { known[$0] } == [photos])
        #expect(LogScope.ancestry(of: root.id) { known[$0] }.isEmpty)
    }

    @Test func roundTripsThroughCodable() throws {
        let scope = LogScope.root(named: "photos").child(named: "album-1")
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(LogScope.self, from: data)
        #expect(decoded == scope)
    }
}
