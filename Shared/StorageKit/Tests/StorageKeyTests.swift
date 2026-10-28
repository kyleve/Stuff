import StorageKit
import Testing

struct StorageKeyTests {
    @Test
    func passesThroughASafeComponent() {
        #expect(StorageKey("logs").name == "logs")
    }

    @Test
    func trimsSurroundingWhitespace() {
        #expect(StorageKey("  logs \n").name == "logs")
    }

    @Test
    func replacesPathSeparatorsAndColons() {
        #expect(StorageKey("a/b").name == "a_b")
        #expect(StorageKey("a\\b").name == "a_b")
        #expect(StorageKey("a:b").name == "a_b")
    }

    @Test
    func neutralizesTraversalAndEmpty() {
        #expect(StorageKey("").name == "_")
        #expect(StorageKey(".").name == "_.")
        #expect(StorageKey("..").name == "_..")
    }

    @Test
    func buildsFromARawRepresentableEnum() {
        enum Keys: String { case logs }
        #expect(StorageKey(Keys.logs).name == "logs")
    }

    @Test
    func acceptsAStringLiteral() {
        let key: StorageKey = "logs"
        #expect(key.name == "logs")
    }

    @Test
    func isValueEquatableByName() {
        #expect(StorageKey("a/b") == StorageKey("a_b"))
        #expect(StorageKey("logs") != StorageKey("notes"))
    }
}
