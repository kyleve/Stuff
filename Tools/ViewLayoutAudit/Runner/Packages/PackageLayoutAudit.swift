@_spi(Testing) import BroadwayUI
@_spi(Testing) import Flyover
@_spi(Testing) import Inspector
@_spi(Testing) import InstallerKitUI
@_spi(Testing) import LifecycleKitUI
@_spi(Testing) import PeriscopeTools
@_spi(Testing) import SnapshotKit
@_spi(Testing) import WhereIntents
@_spi(Testing) import WhereUI

/// Measures package types in one process, independently of native companions.
@main
@MainActor
enum PackageLayoutAudit {
    static func main() throws {
        var records: [String] = []
        records += BroadwayUI._ViewLayoutAuditRegistry.records()
        records += Flyover._ViewLayoutAuditRegistry.records()
        records += Inspector._ViewLayoutAuditRegistry.records()
        records += InstallerKitUI._ViewLayoutAuditRegistry.records()
        records += LifecycleKitUI._ViewLayoutAuditRegistry.records()
        records += PeriscopeTools._ViewLayoutAuditRegistry.records()
        records += SnapshotKit._ViewLayoutAuditRegistry.records()
        records += WhereIntents._ViewLayoutAuditRegistry.records()
        records += WhereUI._ViewLayoutAuditRegistry.records()
        try ViewLayoutAuditRunner.run(records: records)
    }
}
