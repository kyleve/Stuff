# Automation-triggered workflows

Cursor cloud agents (and the automations that schedule them) run on **Linux**,
but this repo targets **iOS/macOS** and needs Xcode + Tuist to build. So the
maintenance jobs that must actually build the app are structured as:

> **Cursor automation** (scheduler, runs weekly) **→ dispatches a GitHub Actions
> workflow** (runs on a macOS `xcode-27` runner) **→ runs the Cursor CLI agent on
> the runner** to do the work and open a PR.

The automation is the thin, prompt-driven scheduler; the workflow is where the
macOS build environment (and the real agent work) lives.

## Workflows

| Workflow | What it does | Trigger |
|----------|--------------|---------|
| [`weekly-build-warnings.yml`](weekly-build-warnings.yml) | Builds the whole tree (`Stuff-iOS-Tests` scheme), has the Cursor CLI agent fix compiler warnings, and opens a PR **only if** there were warnings to fix. | `workflow_dispatch` (dispatched by a weekly Cursor automation) |

## Secrets

Set these once, then every automation-triggered workflow can reuse them.

### GitHub repository/organization secrets (used by the workflow)

- **`CURSOR_API_KEY`** *(required)* — API key for the Cursor CLI agent that runs
  on the macOS runner. Generate it in the Cursor dashboard, then:
  ```bash
  gh secret set CURSOR_API_KEY --repo kyleve/stuff --body "$CURSOR_API_KEY"
  # or org-wide: gh secret set CURSOR_API_KEY --org <org> --visibility all --body "$CURSOR_API_KEY"
  ```
- **`WORKFLOW_PAT`** *(optional but recommended)* — a fine-grained PAT with
  `contents: write` + `pull requests: write` on this repo. When present the
  workflow pushes the fix branch with it so the **opened PR triggers CI**. The
  default `GITHUB_TOKEN` can open the PR but, by GitHub design, will not trigger
  downstream workflows (so CI wouldn't run on the fix PR). If you omit it, kick
  CI on the PR manually (e.g. close/reopen).

### Cursor Cloud Agent secret (used by the automation to dispatch)

- **`GH_DISPATCH_TOKEN`** — a fine-grained PAT with **`actions: write`** on this
  repo, added under **Cursor Dashboard → Cloud Agents → Secrets**. The automation
  uses it to call `workflow_dispatch`. (The Cursor GitHub app can re-run existing
  CI but is not guaranteed to have permission to dispatch an arbitrary workflow,
  so give the automation its own token.)

## Setting up the weekly Cursor automation

Create it at [cursor.com/automations](https://cursor.com/automations) (or with the
`/automate` skill), matching the workflow above:

1. **Trigger** → *Scheduled*, cron `0 9 * * 0` (Sundays 09:00 UTC).
2. **Repository** → single repository, `kyleve/stuff`.
3. **Tools** → leave the base tools on; **turn off "Pull request creation"** (the
   GitHub Action opens the PR, not the automation).
4. **Prompt**:

   ```text
   Dispatch the "Weekly Build Warnings" GitHub Actions workflow on kyleve/stuff so
   it builds on macOS and fixes compiler warnings.

   Run exactly:
     GH_TOKEN="$GH_DISPATCH_TOKEN" gh workflow run weekly-build-warnings.yml \
       --repo kyleve/stuff --ref main

   Then confirm the run started (e.g. `GH_TOKEN="$GH_DISPATCH_TOKEN" gh run list \
   --repo kyleve/stuff --workflow weekly-build-warnings.yml --limit 1`) and report
   the run URL. Do not modify code and do not open a pull request yourself — the
   workflow handles that.
   ```

The workflow does the rest: if the build is already warning-free it makes no
changes and opens no PR; otherwise it opens a `Fix build warnings` PR.

> **No-automation alternative:** if you don't want the Cursor automation layer,
> uncomment the `schedule:` block in `weekly-build-warnings.yml` and GitHub will
> run it on the cron directly. You lose the central Cursor dashboard/run history
> but keep the macOS fix-and-PR behavior.

## Adding another weekly automation

Reuse the same shape:

1. Add a `workflow_dispatch` workflow here that runs on `xcode-27`, sets up mise
   (`jdx/mise-action@v3`), generates the project (`tuist generate --no-open`),
   installs the Cursor CLI, runs `cursor-agent -p --force` with a task-specific
   prompt (restricted autonomy — the agent edits files; CI does git/PR), and
   opens a PR only when the tree changed.
2. Add a Cursor automation whose prompt dispatches that workflow by filename
   (same pattern as above).

Keeping git/PR steps deterministic in the workflow (rather than letting the agent
push) makes runs auditable and lets us enforce repo conventions (SwiftFormat,
branch naming, PR body).
