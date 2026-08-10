import Foundation
import StuffToolCore
import Testing

struct FlakyReportTests {
    @Test func suiteAnalysisFindsSuspectsAndPreservesTheCompatibilityArtifact() throws {
        let failed = try decodeCatalog(fixtureData("flaky-suite-failed", extension: "json"))
        let passed = try decodeCatalog(fixtureData("flaky-suite-passed", extension: "json"))

        let analysis = FlakySuiteAnalysis(catalogs: [failed, passed])

        let identifier = "StuffCoreTests/RaceTests/sometimesFails()"
        #expect(analysis.suspects == [identifier])
        #expect(analysis.stats[identifier] == FlakySuiteStat(
            bundle: "StuffCoreTests",
            name: "sometimesFails()",
            failures: 1,
            seen: 2,
        ))
        let encoded = try #require(
            JSONSerialization.jsonObject(with: analysis.encodedCounts()) as? [String: Any],
        )
        let record = try #require(encoded[identifier] as? [String: Any])
        #expect(record["fails"] as? Int == 1)
        #expect(record["failures"] == nil)
    }

    @Test func tightCountsPreferRepeatedCasesThenFallBackToSummary() throws {
        let repetitions = try decodeCatalog(
            fixtureData("flaky-tight-repetitions", extension: "json"),
        )
        let misleadingSummary = XCResultSummary(failedTests: 0, passedTests: 20)
        #expect(FlakySuiteAnalysis.tightCounts(
            catalog: repetitions,
            summary: misleadingSummary,
        ) == FlakyTightCounts(failures: 1, total: 2))

        let singleCase = try decodeCatalog(Data("""
        {"testNodes":[{"nodeType":"Test Case","name":"one()","result":"Failed"}]}
        """.utf8))
        #expect(FlakySuiteAnalysis.tightCounts(
            catalog: singleCase,
            summary: XCResultSummary(failedTests: 2, passedTests: 8),
        ) == FlakyTightCounts(failures: 2, total: 10))
        #expect(FlakySuiteAnalysis.tightCounts(
            catalog: singleCase,
            summary: nil,
        ) == FlakyTightCounts(failures: 1, total: 1))
    }

    @Test func reportIncludesOnlyNondeterministicTestsAndRendersStableOutput() {
        let suite = FlakySuiteAnalysis(stats: [
            "Bundle/A": FlakySuiteStat(
                bundle: "Bundle",
                name: "A",
                failures: 1,
                seen: 2,
            ),
            "Bundle/B": FlakySuiteStat(
                bundle: "Bundle",
                name: "B",
                failures: 2,
                seen: 2,
            ),
            "Bundle/C": FlakySuiteStat(
                bundle: "Bundle",
                name: "C",
                failures: 1,
                seen: 2,
            ),
            "Bundle/D": FlakySuiteStat(
                bundle: "Bundle",
                name: "D",
                failures: 0,
                seen: 2,
            ),
        ])
        let report = FlakyReport(
            suite: suite,
            tightCounts: [
                "Bundle/A": FlakyTightCounts(failures: 1, total: 2),
                "Bundle/B": FlakyTightCounts(failures: 2, total: 2),
            ],
            suiteRuns: 2,
        )

        #expect(report.rows.map(\.identifier) == ["Bundle/A", "Bundle/C"])
        #expect(report.consoleText(top: 1).contains("2 flaky test(s) detected (showing top 1)"))
        #expect(report.consoleText(top: 1).contains("Bundle/A"))
        #expect(report.consoleText(top: 1).contains("Bundle/C") == false)

        let markdown = report.markdown(
            FlakyReportMetadata(
                date: Date(timeIntervalSince1970: 1_786_320_000),
                suiteRuns: 2,
                iterations: 20,
                relaunch: "YES",
                device: "iPhone 17",
                os: "27.0",
                top: 1,
            ),
        )
        #expect(markdown.contains("suite runs: 2 · tight-loop iterations: 20"))
        #expect(markdown.contains("| `Bundle/A` | Bundle | 1/2 | 1/2 | 50% |"))
        #expect(markdown.contains("_(+1 more not shown; raise `--top` to list them.)_"))
        #expect(markdown.hasSuffix("\n"))
    }
}

private func decodeCatalog(_ data: Data) throws -> XCResultTestCatalog {
    try JSONDecoder().decode(XCResultTestCatalog.self, from: data)
}
