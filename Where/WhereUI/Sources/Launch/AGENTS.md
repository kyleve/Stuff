# Launch and installation-context contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- Keep compatibility monitoring outside disposable scopes. Gate discovery, import recovery, and scope creation before any store open.
  Mask blocked history before teardown. Stop GPS before waiting for launch work or output cleanup.
  Own onboarding completion as one process-model task and drain it during compatibility retirement.
  Guards: `WhereCompatibilityModelTests`, `WhereLaunchTests`, `OnboardingImportRecoveryModelTests`.

- Keep `FileInstallationRecordingContextStore` as the UIKit/FileManager
  adapter for Core's installation-context protocol. Resolve one instance at
  the app root. Inject it into both `WhereModel` and `WhereBootstrap`.
- Persist the installation identity, recording choice with its current-On
  timestamp, stable profile/policy IDs and timestamps, two-phase backup-import
  recovery, and the independent terminal onboarding-import tombstone together
  in the excluded-from-backup sidecar. Never infer confirmation from
  backed-up preferences or migrate it from `UserDefaults`. Persist an explicit
  changed choice when onboarding retries after a later failure.
- Retire the installation sidecar with an atomic directory rename before
  cleanup. Retain the proposed replacement behind `ResetCleanupError` until
  tombstone deletion succeeds (`InstallationRecordingContextStoreTests`).
- Reconcile every pending import after scope resolution but before session
  handoff or recording. Reconcile onboarding imports before offering Restore.
  Acknowledge their preference independently of cleanup. Retain the marker
  through any failure (`WhereLaunchTests`).
- Keep `RootView` passing LifecycleKitUI the stylesheet's positive splash
  minimum and active-scene visibility: the first foreground-visible `MainTabs`
  reveal stays covered when headless promotion coalesces or the first hold is
  interrupted, while warm resumes never replay it.
- A step joins `WhereLaunch`'s plan through `.measured()`. It must declare a
  `budget` (`BudgetedLaunchStep`). See [Spans](../../../Guidance/logging.md#spans). WhereUI also
  owns log retention. `LogHistoryPruner` bounds the store by age *and* event
  count. Both bounds are load-bearing. An age window alone leaves a
  heavy-logging device unbounded inside it.
