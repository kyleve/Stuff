import CoreLocation
import Photos
import Testing
@testable import Where

struct PhotoKitLocationLibraryTests {
    @Test func excludesSharedSyncedUnknownAndHiddenPhotos() {
        let date = Date()
        let location = CLLocation(latitude: 43.65, longitude: -79.38)
        func accepts(
            _ source: PHAssetSourceType,
            hidden: Bool = false,
            offset: TimeInterval = 0,
        ) -> Bool {
            PhotoKitLocationLibrary.observation(
                source: source,
                hidden: hidden,
                capturedAt: date,
                addedAt: date.addingTimeInterval(offset),
                location: location,
            ) != nil
        }
        #expect(accepts(.typeUserLibrary, offset: -300))
        #expect(accepts(.typeUserLibrary, offset: 300))
        #expect(!accepts(.typeUserLibrary, offset: 301))
        #expect(!accepts(.typeUserLibrary, offset: -301))
        #expect(!accepts(.typeCloudShared))
        #expect(!accepts([.typeUserLibrary, .typeCloudShared]))
        #expect(!accepts(.typeiTunesSynced))
        #expect(!accepts([]))
        #expect(!accepts(.typeUserLibrary, hidden: true))
    }
}
