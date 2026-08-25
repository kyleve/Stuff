import Foundation
import ThrowCore

struct EmptyGeographyDataSource: GeographyDataSource {
    func data() async throws -> Data {
        Data(
            """
            {"version":1,"coordinateScale":10000,"source":{"name":"Fixture","release":"1","scale":"fixture"},"paths":[]}
            """.utf8,
        )
    }
}
