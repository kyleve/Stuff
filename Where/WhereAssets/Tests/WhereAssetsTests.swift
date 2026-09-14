import Foundation
import Testing
import WhereAssets

struct WhereAssetsTests {
    @Test func ownsACompiledAssetCatalog() throws {
        let catalog = try #require(WhereAssetBundle.bundle.url(
            forResource: "Assets",
            withExtension: "car",
        ))
        #expect(try Data(contentsOf: catalog).isEmpty == false)
    }
}
