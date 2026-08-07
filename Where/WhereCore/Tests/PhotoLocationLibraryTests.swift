import Foundation
import Testing
@testable import WhereCore

struct PhotoLocationLibraryTests {
    @Test func unavailableLibraryNeverPromptsOrReturnsAssets() async throws {
        let library = UnavailablePhotoLocationLibrary()
        #expect(await library.authorizationStatus() == .denied)
        #expect(await library.requestAuthorization() == .denied)
        #expect(try await library.assets(in: DateInterval(start: .distantPast, end: .now)) == [])
    }
}
