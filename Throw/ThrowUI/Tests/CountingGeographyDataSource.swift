import Foundation
import ThrowCore

actor CountingGeographyDataSource: GeographyDataSource {
    private(set) var loadCount = 0

    func data() async throws -> Data {
        loadCount += 1
        return Data(
            """
            {"version":2,"coordinateScale":10000,"sources":[{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],"paths":[{"kind":"coastline","detailLevel":"wide","bounds":[369000,-1221000,371000,-1219000],"coordinates":[370000,-1221000,0,2000]}]}
            """.utf8,
        )
    }
}
