import Foundation
import StuffToolCore
import Testing

struct CatalogSerializerTests {
    @Test func sortsKeysByUTF8AndMatchesXcodeSpacing() throws {
        let object: [String: Any] = [
            "appIcon.title": "App Icon",
            "Log today here": "Log today here",
            "items": [1, true],
        ]

        let data = try CatalogSerializer().data(from: object)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text == """
        {
          "Log today here" : "Log today here",
          "appIcon.title" : "App Icon",
          "items" : [
            1,
            true
          ]
        }
        """)
    }

    @Test func rendersEmptyContainersLikeXcode() throws {
        let data = try CatalogSerializer().data(from: ["array": [], "object": [:]])
        let text = String(decoding: data, as: UTF8.self)

        #expect(text == """
        {
          "array" : [

          ],
          "object" : {

          }
        }
        """)
    }
}
