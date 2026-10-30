import Foundation
import Testing
import ViewDocumentCore

struct ViewImageDescriptorTests {
    @Test(arguments: [ViewImageDescriptor.Sizing.fit, .fill, .tile(scale: 0.5)])
    func checksResourcesAndRoundTrips(sizing: ViewImageDescriptor.Sizing) throws {
        let asset = ViewAssetID(rawValue: "illustration")
        let document = ViewDocument(schemaVersion: 1, root: documentNode(
            "art",
            content: .raster(.init(asset: asset, sizing: sizing)),
        ))
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: document,
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        let resources = ViewDocumentResources(images: [asset], symbols: [])
        let decoded = try ValidatedViewDocument.decode(
            JSONEncoder().encode(document),
            resources: resources,
            limits: .standard,
        )
        #expect(decoded.document == document)
        #expect(decoded.resources.images == [asset])
    }

    @Test(arguments: [Double.nan, .infinity, 0, 0.01, 11])
    func rejectsExtremeTileDensity(scale: Double) {
        let asset = ViewAssetID(rawValue: "illustration")
        let document = ViewDocument(schemaVersion: 1, root: documentNode(
            "art",
            content: .raster(.init(asset: asset, sizing: .tile(scale: scale))),
        ))
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: document,
                resources: .init(images: [asset], symbols: []),
                limits: .standard,
            )
        }
    }
}
