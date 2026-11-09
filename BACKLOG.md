# Stuff backlog

[Linear’s Stuff team](https://linear.app/kve/team/STU/all) owns all actionable work for this repository.
The team key is `STU`; the workspace is `kve`.
Human notes start in [Triage](https://linear.app/kve/team/STU/triage).
Verified findings enter Backlog directly.

The repository keeps architecture rules in `AGENTS.md` and a dated technical report in `MODULE_AUDIT.md`.
The migration manifest is a historical receipt, not an editable backlog or a periodic export.

## Views

- [Open Backlog](https://linear.app/kve/view/a3d4ea426c51)
- [Must Do](https://linear.app/kve/view/ca2800e5a2d6)
- [Quick Wins](https://linear.app/kve/view/5405f8960080)
- [Needs Design](https://linear.app/kve/view/f4bd7d364e9d)
- [Exploratory](https://linear.app/kve/view/0d5ec7e79f6c)
- [Human Requests](https://linear.app/kve/view/af855c9b4bb6)
- [Completed History](https://linear.app/kve/view/613f0d67d9a6)

Area views are available in the Stuff team’s Views page. Completed History covers unarchived completed issues; use archives for older work.

## Access

The root npm dependencies pin `@schpet/linear-cli`.
Run `mise exec -- npm ci` after a lockfile change.
Use the repository binary so automated runs use the same version:

```sh
mise exec -- node_modules/.bin/linear --workspace kve --no-input team list --json
mise exec -- node_modules/.bin/linear --workspace kve --no-input issue list --team STU --all-assignees --all-states --limit all --json
mise exec -- node_modules/.bin/linear --workspace kve --no-input issue view STU-123
```

Replace `STU-123` with an observed identifier.
Use macOS Keychain credentials locally, or inject `LINEAR_API_KEY` through the remote environment’s secret store.
Never commit credentials or print a token.
The repository configuration contains only the workspace, team, and sorting preference.

An authentication, network, rate-limit, or GraphQL error means access is incomplete.
Report that limitation and preserve unsent findings in the task handoff.
Do not report an empty backlog, close an issue, or recreate Markdown TODO files as a fallback.

The CLI’s default list excludes other assignees and most states.
Use explicit team, state, assignee, and pagination options.
For history and duplicate searches, include archived issues through the API:

```sh
mise exec -- node_modules/.bin/linear --workspace kve --no-input api --paginate 'query($after: String) {
  issues(first: 100, after: $after, includeArchived: true,
    filter: {team: {id: {eq: "58134eca-7005-4b28-bffc-3243ca696a1e"}}}) {
    nodes { id identifier title description url archivedAt state { name type } }
    pageInfo { hasNextPage endCursor }
  }
}'
```

Search descriptions as well as titles for symbols, paths, and prior proposals.
Read matching issues and their comments before changing them.
Archived issues remain part of the history; restore one before editing it.

## Issue content and organization

Use a short, concrete title. Put these details in the Markdown description:

- The problem or requested outcome, with its user-visible consequence.
- Evidence: repository-relative paths, symbols, and current line references.
- A suggested fix and acceptance conditions. Preserve unresolved design questions.
- Provenance: human, audit, agent, or PR review, with the recorded date or reference.
- Verification date, source revision, and any runtime or environment limits.

Preserve original errors, uncertainty, corrections, and human intent.
Do not invent a date, measured result, or acceptance condition.
Use commit-pinned GitHub links for historical evidence and Linear links for related work.

| Property | Rule |
| --- | --- |
| Area | Ungrouped `area:` labels for repository areas, such as `area:Where` or `area:Repo` |
| Module | Ungrouped `module:` labels; apply all relevant modules to cross-cutting work |
| Type | One label from `Type`: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `design`, `convention`, or `localization` |
| Effort | One label from `Effort category`: `quick-win` or `needs-design`; omit when unknown |
| Origin | `origin:human`, `origin:audit`, `origin:review`, or `origin:agent`, plus the original attribution text |
| Priority | High = must do; Medium = should do; Low = nice to have |
| Exploration | `exploratory` with no priority until the direction becomes actionable |

Reserve Urgent for actual urgency. Existing priorities are human decisions.
Explain a proposed priority change instead of silently applying it during maintenance.
Do not infer assignees, deadlines, estimates, projects, or cycles from an audit date or a source-file location.
Use projects for bounded efforts with an outcome, rather than permanent module containers.

Use sub-issues for independently actionable parts of a larger task.
Add an explicit blocking relation only when work depends on another task.
Supporting evidence and alternatives remain in the description.

## State and closure

Human submissions remain in Triage until verification establishes their meaning and evidence.
Accepted work enters Backlog. Selected work moves to Todo or In Progress.
An open implementation PR uses In Review.

Mark an issue Done only after verifying the merged implementation and its acceptance conditions.
Keep partial fixes open and describe the remaining work.
A visual requirement needs rendered evidence; navigation and reachability need runtime evidence.
A static audit cannot establish those results.
Use Canceled or Duplicate with an explanation when a proposal is declined or already tracked.
Link a duplicate to its canonical issue. Never silently delete history.

Automatic closing and parent/child completion cascades are disabled.
Linear requires automatic archiving; Stuff uses the longest supported period, 12 months.
Agents must include archives in historical searches.

During authorized implementation, review, or triage, agents update Linear directly with evidence.
Run summaries list created, materially changed, and closed issues.
Code and documentation changes still require the repository’s checks and PR workflow.
Link affected issues from PR descriptions and deferred-review replies.

## Maintenance

Use the [todo-triage skill](.agents/skills/todo-triage/SKILL.md) for intake, findings, closure, and weekly audits.
`MODULE_AUDIT.md` remains a dated report of verified code and cross-cutting themes.
It carries Linear links, not a second list of actionable work.

The one-time migration is documented in [the migration record](Tools/BacklogMigration/README.md).
Historical descriptions retain their original meaning; import is not a fresh source verification.
Known completion dates use native fields. User-approved creation-date estimates are explicitly labeled in imported issues.
These one-time estimates do not authorize agents to invent dates during normal backlog maintenance.
