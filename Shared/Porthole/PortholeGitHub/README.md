# PortholeGitHub

PortholeGitHub provides native GitHub sign-in, repository editing, draft pull requests, and CI status for Porthole.
It uses Foundation, Security, and CryptoKit. It has no shell or Git executable dependency.

## Integration

Inject a `GitHubHTTPTransport`, `GitHubCredentialStore`, and registered GitHub App client ID.
The host owns the UI and the approval boundary. This module never starts sign-in or publication on its own.

1. Enable device flow for the GitHub App registration.
2. Give the app repository Contents and Pull requests write access, plus Checks and Commit statuses read access.
3. Construct `GitHubDeviceFlow` with the registered client ID.
4. Call `begin(at:)` and show its user code and verification URL.
5. Schedule `poll(at:)` at the returned `nextPollAt` until authorization completes or the screen closes.
6. Fetch a `GitHubRepositorySnapshot` through `GitHubRepositoryClient.snapshot`.
7. Construct a `GitHubSourceWorkspace` with that snapshot and the installed source evidence.
8. Apply explicit text edits to the workspace.
9. Create a `GitHubPullRequestProposal` and show its `diff`, title, body, repository, and base commit.
10. After approval, pass that exact proposal to `GitHubPublisher.publish`.
11. Read `ciStatus` for the returned commit.

GitHub App permissions also depend on the installation and the user's repository access.
Device flow needs no client secret. An expired access token requires sign-in again.
The client validates the GitHub user before it saves a token.
Credentials stay in a device-only Keychain item and never enter a proposal.
The host must exclude this module from automatic runtime export and expose approved operations through its native executor.

## Source and review

The installed source and repository base are separate immutable values.
A dirty installed build does not seed repository edits. The proposal records its build identity and dirty status as evidence.
The repository base carries a fixed commit and tree. Its complete path inventory prevents an unloaded existing file from becoming an accidental addition.
Use `snapshot(base:paths:maximumFileBytes:)` to load more files from that saved tree. This method never resolves the branch again.
It returns the requested files with the original repository, branch, commit, tree, and complete path inventory.
The workspace loads selected UTF-8 files on demand. Symlinks, submodules, binary files, oversized files, and truncated tree responses produce errors.
The base tree preserves every unchanged repository file.

The diff uses complete file hunks and preserves mode and trailing-newline changes.
Approvals apply to the immutable proposal. Later workspace edits require another proposal and review.
Each proposal declares whether its description and changed files contain synthetic examples or personal diagnostic evidence.
Use invented values for regression fixtures by default. The phone requires a separate selection before it publishes a proposal declared personal.
That selection binds to the proposal fingerprint and does not carry to another review.
The declaration is a review boundary, not an automatic personal-data classifier. Reviewers must inspect both the description and patch.
Proposal Codable field names form the persisted v1 contract. Existing review codes remain unchanged; `publicationUncertain` is an additional v1 code.
Incompatible changes to the stored fields require an explicit versioned successor.

## Publication and retries

`GitHubWorkspaceStore` persists a revisioned workspace and its saved review.
Edits require the current revision and invalidate the previous review.
Loading more files at the same commit preserves existing edits.
Changing the repository base requires an empty patch.
`GitHubWorkspaceEditing` exposes local edits and reads; it cannot publish.
Before `beginPublication` returns, the store atomically saves `publicationUncertain` with the exact proposal.
If that save fails, publication cannot begin. The existing review remains unchanged in memory.
An interrupted or failed attempt keeps this saved proposal locked, including after relaunch.
File loading, editing, removal, discard, and new reviews remain unavailable until the same proposal reconciles with GitHub.
`publicationFailed` ends the active attempt but preserves the lock. Retry the saved proposal through `beginPublication` and the publisher.
A successful `finishPublication` saves the published result and permits workspace changes again.
Publication completion and failure require the exact proposal ID and fingerprint. A late callback cannot unlock or overwrite another publication.

`GitHubConfigurableClient` accepts a public GitHub App client ID after installation.
It stores that public ID separately from Keychain user credentials.
No authentication request runs before configuration.

The proposal fixes the branch name, parent commit, author, commit date, contents, and publication marker.
GitHub creates content-addressed trees and commits. Repeating those calls produces the same Git objects.
The publisher creates a new branch and never updates or force-pushes an existing branch.
An existing branch must reference the expected commit.

After an uncertain branch or pull-request write, the publisher reads GitHub state before it continues.
A matching pull request includes the proposal marker, commit, and base branch.
An existing closed or promoted request remains the publication result.
An inconclusive read produces `publicationUncertain`; it never means that the write failed.
Persist the proposal before publication. Retry the same proposal after interruption or app restart.
The publisher binds the reviewed author to its task. Every repository request checks its loaded credential against that account before dispatch.
A refreshed token for the same account can continue. A different account stops further publication requests.
The saved proposal remains locked after failure. Sign in with its original account and retry to reconcile the remote result.
Authentication and permission errors remain observable.

The target branch can advance after the workspace capture. The proposal keeps its original parent and does not silently rebase.
The phone review identifies that original base commit. GitHub computes the pull-request comparison against the current target branch.
Review the current GitHub diff and CI before merging. Publication creates a draft request and never merges it.

## CI and tests

CI status combines check runs and commit statuses, including external services such as CircleCI.
No reported checks means pending. Unknown conclusions remain unknown.
The caller owns polling and cancellation. The module does not create a background task or trigger a CI workflow manually.

`PortholeGitHubTests` uses scripted HTTP and publication remotes. No test authenticates with GitHub or creates a remote branch or pull request.
The Keychain test uses an isolated service and synthetic token, then removes its item.
Tests cover publication locks after failure and relaunch, failed lock persistence, and retries that create one branch and one pull request.
They also cover fixed-base reads after branch advancement, file limits, dirty source separation, polling, identity validation, branch collisions, and CI state.
Scripted credential changes verify each publication boundary and permit token refresh for the reviewed account.

API references: [device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow),
[Git trees](https://docs.github.com/en/rest/git/trees), and [pull requests](https://docs.github.com/en/rest/pulls/pulls).
