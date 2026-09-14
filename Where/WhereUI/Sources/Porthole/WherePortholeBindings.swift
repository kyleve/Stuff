import BroadwayCore
import BroadwayUI
import CreditKit
import Flyover
import Inspector
import JournalKit
import LifecycleKit
import LifecycleKitUI
import PeriscopeCore
import PeriscopeTools
import PeriscopeUI
import PortholeRuntime
import RegionKit
import SnapshotKit
import WhereAssets
import WhereCore

/// The adopting feature installs catalogs from its process dependency graph only after activation.
enum WherePortholeBindings {
    static func install(in registry: PortholeRegistry, scope: PortholeScopeToken) async throws {
        try await BroadwayCore.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await BroadwayUI.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await CreditKit.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await JournalKit.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await LifecycleKit.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await LifecycleKitUI.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await PeriscopeCore.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await PeriscopeUI.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await PeriscopeTools.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await SnapshotKit.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await RegionKit.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await WhereCore.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await WhereAssets.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await PortholeGeneratedModule.install(in: registry, scope: scope)
        try await Flyover.PortholeGeneratedModule.install(in: registry, scope: scope)
        try await Inspector.PortholeGeneratedModule.install(in: registry, scope: scope)
    }
}
