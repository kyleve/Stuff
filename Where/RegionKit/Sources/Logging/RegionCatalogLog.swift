import PeriscopeCore

/// Structured events for `RegionCatalog`'s bundled-manifest load.
@LogScope("RegionCatalog")
enum RegionCatalogLog {
    enum SpanName: Hashable {
        case loadManifest
    }

    @LogEvent(
        "missing-manifest",
        level: .fault,
        message: "Missing required bundled regions.json manifest",
    )
    struct MissingManifest {}

    @LogEvent("loaded", level: .info)
    struct Loaded {
        @LogField("region_count", exposure: .shareable, kind: .count)
        var regionCount: Int

        var message: String {
            "Loaded region catalog with \(regionCount) region(s)"
        }
    }

    @LogEvent("decode-failed", level: .fault)
    struct DecodeFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to decode bundled regions.json: \(description)"
        }
    }
}
