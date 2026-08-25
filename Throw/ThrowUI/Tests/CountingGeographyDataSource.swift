import Foundation
import ThrowCore

actor CountingGeographyDataSource: GeographyDataSource {
    private(set) var loadCount = 0

    func data() async throws -> Data {
        loadCount += 1
        return Data(
            """
            {"version":1,"coordinateScale":10000,"source":{"name":"Fixture","release":"1","scale":"fixture"},"paths":[{"kind":"coastline","minimumZoomTenths":0,"scaleRank":0,"bounds":[369000,-1221000,371000,-1219000],"coordinates":[370000,-1221000,0,2000]}]}
            """.utf8,
        )
    }
}
