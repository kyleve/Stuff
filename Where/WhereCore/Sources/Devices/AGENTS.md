# Recording-device contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- **`DeviceRecordingController` owns this installation's local recording choice
  and physical GPS state.** Serialize mutations across awaits. Fail closed when
  the current identity is removed. Stamp every ingested GPS sample with the
  current installation id. Apply `LocationHistoryReader` to every user-facing
  projection. Persist immutable profiles, nickname events, global removal
  tombstones, and target-owned advisory check-ins separately. A remote device
  may rename or remove an identity. It must never change another installation's
  local consent. Backups alone read lossless raw samples and device/removal
  timelines, excluding non-restorable check-ins.
- Keep historical device-name lookups inclusive of removed profiles.
  Use the latest saved nickname or the profile's hardware name.
