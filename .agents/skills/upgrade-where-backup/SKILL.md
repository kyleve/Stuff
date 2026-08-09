---
name: upgrade-where-backup
description: Upgrade a Where app backup directory or ZIP with Where/Tools/upgrade-backup.rb. Verify archive integrity and record preservation. Prove the result loads through WhereCore BackupService. Use when a user asks to upgrade, migrate, repair, validate, or test-import a legacy Where backup.
---

# Upgrade a Where backup

Read the root `AGENTS.md`, `Where/AGENTS.md`, and `Where/WhereCore/AGENTS.md`. Load the `running-tests` skill. Verification must run through `./test`.

Run the bundled driver from the repository root:

```bash
ruby .agents/skills/upgrade-where-backup/scripts/upgrade_and_verify.rb INPUT [OUTPUT]
```

`INPUT` may be an unpacked backup directory or ZIP. `OUTPUT` defaults to a sibling named `<input>-upgraded.zip`. The driver:

1. Reads the source manifest and records the counts that migration must preserve.
2. Creates a temporary input ZIP when necessary.
3. Runs the repository's pinned Ruby and `Where/Tools/upgrade-backup.rb`.
4. Checks ZIP integrity, the current manifest version, required tables, and counts.
5. Writes the backup path and expected counts to a temporary JSON configuration.
6. Enables and runs `BackupServiceTests.upgradedBackupDecodesAndLoadsAssets` through `./test`. It exercises `BackupService.readArchive(at:)` and all referenced asset bytes. The test is compiled but disabled during normal runs.

Keep every manifest transformation in `Where/Tools/upgrade-backup.rb`. The driver only packages input, invokes that authority, and independently verifies its output. Do not duplicate migration rules in the skill.

## Safety and recovery

- Do not modify or delete the input.
- Do not pass `--force` unless the user explicitly approves replacing the exact output path. Without it, an existing output is rejected.
- Expect filesystem approval when the output is outside the workspace.
- The upgraded ZIP remains available if Swift verification fails. Diagnose the failure. Do not represent the backup as verified.

## Handoff

Report the output path, source and destination format versions, preserved record counts, ZIP result, Ruby regression result, Swift production-decoder result, and whether the repository is clean. Do not expose backup contents in logs or the response.
