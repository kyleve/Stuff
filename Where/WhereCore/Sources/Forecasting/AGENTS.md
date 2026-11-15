# Forecasting contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- **Resolve planned stays independently by their stable stay identity.** Order revisions by
  `updatedAt` then revision UUID. Delete with a newer nil tombstone. Retain completed plans
  (`PlannedStayCoordinatorTests`).
- **Keep forecast home intent separate from tracked regions and display preferences.** A nil
  home-register revision selects historical estimates. Read both planning registers in one
  `readSnapshot`. Never write plans into recorded presence (`PlannedStayCoordinatorTests`).
- **Validate planning windows at store and backup boundaries.** Use inclusive `CalendarDay`
  endpoints with latest arrival no later than earliest departure. Preserve all revision identities
  and tombstones during backup restore (`BackupServiceTests`, `BackupCoordinatorTests`).
- **Keep planned-stay location checks advisory.** `PlannedStayLocationVerifier` accepts a fix
  inside the region or within the configured drift threshold outside its boundary. Do not add
  horizontal accuracy to the threshold.
