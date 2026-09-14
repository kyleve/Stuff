# PortholeGitHub

- Bind publication completion and failure to the same proposal identity used to start it.
- Require the native host to approve personal diagnostic evidence for the exact saved proposal before publication.

- Save the publication-uncertain review atomically before returning its proposal. Keep failed and restored publications locked until that proposal reconciles.
- Persist the exact proposal before publication. Never publish through `GitHubWorkspaceEditing` or a generated diagnostic capability.
- Require the current workspace revision for edits; invalidate a prepared review when its patch changes.
- Keep the public App client ID separate from Keychain user credentials.

PortholeGitHub owns native GitHub authentication, repository workspaces, reviewed publication, and CI reads. See [README.md](README.md).
Read the [Porthole contract](../AGENTS.md) and the [repository contract](../../../AGENTS.md) before editing this module.

- Use Foundation, Security, and CryptoKit only. Keep UI, app domain types, and provider-specific AI code outside this module.
- Exclude this credential-bearing module from automatic runtime export. Route public user operations through the host's native approval executor.
- Keep installed source evidence separate from the immutable repository base and explicit edits.
- Persist the approved proposal before publication. Reuse its identity, author, date, and content during retries.
- Bind the reviewed account to the entire publication task. Verify each request’s loaded credential before dispatch; permit token refresh only for that account.
- Reconcile uncertain writes through GitHub reads. Never force-push, recreate a conflicting branch, or treat an inconclusive response as failure.
- Fetch additional workspace files from the recorded tree and blob IDs. Never resolve the branch again for an existing base.
- Preserve the base tree for unedited files. Reject edits to existing files whose base content was not loaded.
- Treat Codable proposal field names as the persisted v1 contract. Add an explicit versioned successor for incompatible changes.
- Keep tokens inside the credential boundary. Never log response bodies or authenticated requests.
- Use scripted remotes for tests. The isolated Keychain test stores synthetic data only.

Run `swift test --package-path Shared/Porthole --filter PortholeGitHubTests`. Keep tests paired with their source files.
