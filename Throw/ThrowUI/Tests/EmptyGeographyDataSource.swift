import Foundation
import ThrowCore

struct EmptyGeographyDataSource: GeographyDataSource {
    func data() async throws -> Data {
        Data(
            """
            {"version":2,"coordinateScale":10000,"sources":[{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],"paths":[]}
            """.utf8,
        )
    }
}
