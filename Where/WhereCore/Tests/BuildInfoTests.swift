import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers reading build metadata out of an Info.plist dictionary: the stamped
/// app bundle, the unstamped ones (RegionViewer, the test host, extensions), and
/// the degraded stamps the script writes when git can't answer.
struct BuildInfoTests {
    private func info(
        version: String? = "1.4",
        build: String? = "27",
        sha: String? = "a18a9309c5d6",
        status: String? = "clean",
    ) -> [String: String] {
        var info: [String: String] = [:]
        if let version { info["CFBundleShortVersionString"] = version }
        if let build { info["CFBundleVersion"] = build }
        if let sha { info["WhereGitSHA"] = sha }
        if let status { info["WhereGitStatus"] = status }
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
        let buildInfo = BuildInfo(infoDictionary: info(sha: nil, status: nil))
        #expect(buildInfo.version == "1.4")
        #expect(buildInfo.commit == nil)
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
}
