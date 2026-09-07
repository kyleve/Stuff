@testable import DaylightCore
import Foundation
import Testing

struct ImageRecipeTests {
    @Test func recipeRoundTripAndUnknownVersion() throws {
        var recipe = ImageRecipe.original
        recipe.preset = .warm
        recipe.shadows = 0.3
        #expect(try JSONDecoder()
            .decode(ImageRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
        recipe.version = 2
        #expect(throws: DaylightError.self) { try recipe.validate() }
    }
}
