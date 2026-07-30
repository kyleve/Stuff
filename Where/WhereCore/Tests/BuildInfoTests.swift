import Foundation
import PeriscopeCore
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers reading build metadata out of an Info.plist dictionary: the stamped
/// app bundle, the unstamped ones (RegionViewer, the test host, extensions), and
/// the degraded stamps the script writes when git or a build setting can't
/// answer.
struct BuildInfoTests {
    private func info(
        version: String? = "1.4",
        build: String? = "27",
        sha: String? = "a18a9309c5d6",
        status: String? = "clean",
        configuration: String? = "Release",
        optimizationLevel: String? = "-O",
        compilationMode: String? = "singlefile",
    ) -> [String: String] {
        var info: [String: String] = [:]
        if let version { info["CFBundleShortVersionString"] = version }
        if let build { info["CFBundleVersion"] = build }
        if let sha { info["WhereGitSHA"] = sha }
        if let status { info["WhereGitStatus"] = status }
        if let configuration { info["WhereConfiguration"] = configuration }
        if let optimizationLevel { info["WhereSwiftOptimizationLevel"] = optimizationLevel }
        if let compilationMode { info["WhereSwiftCompilationMode"] = compilationMode }
        return info
    }

    @Test func readsAStampedBundle() {
        let buildInfo = BuildInfo(infoDictionary: info())
        #expect(buildInfo.version == "1.4")
        #expect(buildInfo.build == "27")
        #expect(buildInfo.commit == BuildInfo.Commit(sha: "a18a9309c5d6", isDirty: false))
    }

    @Test func marksACommitBuiltFromADirtyTree() {
        let buildInfo = BuildInfo(infoDictionary: info(status: "dirty"))
        #expect(buildInfo.commit?.isDirty == true)
        #expect(buildInfo.commit?.sha == "a18a9309c5d6")
    }

    @Test func reportsNoCommitForAnUnstampedBundle() {
        // The RegionViewer / StuffTestHost case: versions present, no stamp.
        let buildInfo = BuildInfo(
            infoDictionary: info(
                sha: nil,
                status: nil,
                configuration: nil,
                optimizationLevel: nil,
                compilationMode: nil,
            ),
        )
        #expect(buildInfo.version == "1.4")
        #expect(buildInfo.commit == nil)
        #expect(buildInfo.compilation == nil)
    }

    @Test func readsHowTheBuildWasCompiled() {
        let buildInfo = BuildInfo(infoDictionary: info())
        #expect(
            buildInfo.compilation == BuildInfo.Compilation(
                configuration: "Release",
                optimizationLevel: "-O",
                mode: "singlefile",
            ),
        )
    }

    /// The compilation mode is the least load-bearing of the three, so a build
    /// that didn't export one still reports the optimization level — which is
    /// the field the whole reading exists for.
    @Test func readsTheOptimizationLevelWithoutACompilationMode() {
        let buildInfo = BuildInfo(infoDictionary: info(compilationMode: nil))
        #expect(buildInfo.compilation?.optimizationLevel == "-O")
        #expect(buildInfo.compilation?.mode == nil)
    }

    @Test func treatsAnUndeterminedCompilationValueAsAbsent() {
        // The script writes `unknown` for a build setting Xcode didn't export;
        // reporting that literal would read as a real optimization level.
        #expect(BuildInfo(infoDictionary: info(optimizationLevel: "unknown")).compilation == nil)
        #expect(BuildInfo(infoDictionary: info(configuration: "unknown")).compilation == nil)
        #expect(BuildInfo(infoDictionary: info(compilationMode: "unknown")).compilation?
            .mode == nil)
    }

    @Test func reportsNoCompilationForAHalfWrittenStamp() {
        #expect(BuildInfo(infoDictionary: info(configuration: nil)).compilation == nil)
        #expect(BuildInfo(infoDictionary: info(optimizationLevel: nil)).compilation == nil)
    }

    @Test func reportsNoCommitWhenTheStampCouldNotReadGit() {
        // A checkout without git metadata: the script still writes both keys.
        let buildInfo = BuildInfo(infoDictionary: info(sha: "unknown", status: "unknown"))
        #expect(buildInfo.commit == nil)
    }

    @Test func reportsNoCommitForAHalfWrittenStamp() {
        #expect(BuildInfo(infoDictionary: info(status: nil)).commit == nil)
        #expect(BuildInfo(infoDictionary: info(sha: nil)).commit == nil)
    }

    @Test func reportsNoCommitForAnUnrecognizedStatus() {
        // A status the reader doesn't know is not silently treated as clean.
        #expect(BuildInfo(infoDictionary: info(status: "probably-fine")).commit == nil)
    }

    @Test func treatsBlankValuesAsAbsent() {
        let buildInfo = BuildInfo(infoDictionary: info(version: "", build: "  ", sha: ""))
        #expect(buildInfo.version == nil)
        #expect(buildInfo.build == nil)
        #expect(buildInfo.commit == nil)
    }

    @Test func readsTheHostBundleWithoutTrapping() {
        // StuffTestHost is unstamped, so this only pins that reading a real
        // bundle is safe and honest — not any particular value.
        let buildInfo = BuildInfo.current(bundle: .main)
        #expect(buildInfo.commit == nil)
    }

    @Test func vendsEveryStampedFactAsASessionAttribute() {
        let buildInfo = BuildInfo(infoDictionary: info())
        #expect(buildInfo.logSessionAttributes == [
            .commit: "a18a9309c5d6",
            .commitStatus: "clean",
            .configuration: "Release",
            .optimizationLevel: "-O",
            .compilationMode: "singlefile",
        ])
    }

    @Test func marksADirtyTreeInTheSessionAttributes() {
        let buildInfo = BuildInfo(infoDictionary: info(status: "dirty"))
        #expect(buildInfo.logSessionAttributes[.commitStatus] == "dirty")
    }

    @Test func omitsAnUnexportedCompilationModeFromTheSessionAttributes() {
        let buildInfo = BuildInfo(infoDictionary: info(compilationMode: nil))
        #expect(buildInfo.logSessionAttributes[.compilationMode] == nil)
        #expect(buildInfo.logSessionAttributes[.optimizationLevel] == "-O")
    }

    /// An unstamped bundle claims nothing rather than claiming it was built from
    /// a commit named `unknown` — a session that can't name its build should
    /// read as unidentified, not as a build called "unknown".
    @Test func vendsNoSessionAttributesForAnUnstampedBundle() {
        let buildInfo = BuildInfo(
            infoDictionary: info(
                sha: nil,
                status: nil,
                configuration: nil,
                optimizationLevel: nil,
                compilationMode: nil,
            ),
        )
        #expect(buildInfo.logSessionAttributes.isEmpty)
    }
}
