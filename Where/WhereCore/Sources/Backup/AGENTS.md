# Backup contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- **Export backups from one `readSnapshot` and keep restorable user data
  lossless.** Preserve optional motion and every sample-attribution revision,
  including reset tombstones. Add persisted user-data shapes end-to-end and cover both import
  strategies. Export no target-owned recording check-ins. Ignore any in an
  imported archive (`BackupServiceTests` / `BackupCoordinatorTests`).
- **Backup import never adopts or changes local recording consent.** Archives
  omit that device-local choice. Replace preserves it and every existing
  removal tombstone while rotating the data generation and discarding the local
  outbox (`BackupCoordinatorTests`).
- **Gate import recovery with a two-phase sidecar plus an atomic store
  receipt.** Never clear a committed onboarding marker before its independent
  terminal completion tombstone
  (`BackupCoordinatorTests` / `WhereLaunchTests`).
- **Keep the backup archive strict synthesized `Codable`.** A shape change
  bumps `BackupArchive.currentFormatVersion` and extends
  [`../Tools/upgrade-backup.rb`](../../../Tools/upgrade-backup.rb). Never add an
  in-code legacy decode fallback.
