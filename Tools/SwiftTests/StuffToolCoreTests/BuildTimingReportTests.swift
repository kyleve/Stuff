import Foundation
@testable import StuffToolCore
import Testing

struct BuildTimingReportTests {
    @Test func parsesAndRanksBuildPhasesAndTypeChecks() throws {
        let report = try BuildTimingReport(
            log: fixtureData("profile-build", extension: "log"),
        )

        #expect(report.phases == [
            BuildPhaseTiming(name: "CompileSwiftSources", tasks: 10, seconds: 12.5),
            BuildPhaseTiming(name: "CompileAssetCatalog", tasks: 1, seconds: 2.5),
        ])
        #expect(report.typeChecks == [
            TypeCheckTiming(
                location: "Where/WhereCore/Sources/Slow.swift:10:5",
                milliseconds: 240,
            ),
            TypeCheckTiming(
                location: "Shared/Broadway/Sources/Other.swift:2:1",
                milliseconds: 120,
            ),
        ])
        let text = report.text(typeCheckThreshold: 100)
        #expect(text.contains("83%  CompileSwiftSources (10)"))
        #expect(text.contains("240ms  Where/WhereCore/Sources/Slow.swift:10:5"))
    }

    @Test func missingSummaryRendersAnHonestEmptyReport() {
        let text = BuildTimingReport(log: Data()).text(typeCheckThreshold: 100)

        #expect(text.contains("no build-timing summary found"))
        #expect(text.contains("none — no expression"))
    }
}
