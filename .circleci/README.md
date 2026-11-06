# CI and publication

CircleCI runs all validation, signed archives, Flyover captures, release publication, and site builds.
GitHub hosts the repository, PRs, releases, and Pages.
The only Actions workflow uploads the prepared site to Pages and reports its result.
GitHub requires an Actions OIDC token for that deployment API.
This bridge also avoids the branch-publishing limit of ten Pages builds per hour.
See [GitHub's deployment API](https://docs.github.com/en/rest/pages/pages#create-a-github-pages-deployment)
and [Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits).

## Validation

[`config.yml`](config.yml) selects work before allocating a Mac.
[`jobs.yml`](jobs.yml) defines all executors, commands, and jobs.
[`continue.yml`](continue.yml) defines the complete `iOS CI` gate; its existing check identity remains unchanged.
The gate includes lint, retained tools, web tests, architecture, host tests, iOS tests, snapshots, and release-audience builds.
Documentation-only PRs complete that gate on Linux.
Web checks and Chromium tests use Linux.
WebKit tests share the existing architecture/host Mac job and its installed dependencies.
Linux WebKit stalled rendering in the high-density atlas fixtures; macOS retains the previous browser platform.

To validate an explicit stack tip, run:

```bash
python3 -m Tools.ci_request ci --branch codex/example
```

The command uses the authenticated `circleci` CLI and [`project.json`](project.json).
It sets `manual_full_gate=true` for both config and checkout on that branch.
Ordinary PR and main events do not need that override.

## Publication

A GitHub custom webhook triggers [`webhook.yml`](webhook.yml) with config and checkout fixed to `main`.
It handles main pushes and PR opening, reopening, synchronization, labels, and closure.
The controller reads live PR state, so delayed deliveries cannot restore an obsolete label or head.
Forks never receive signing credentials.

[`ci_publication.py`](../Tools/ci_publication.py) generates native job dependencies from the trusted app registry.
Each app/channel has a serial job group.
The signed worker receives only the signing context; the Linux publisher receives only the GitHub context.
Verified IPAs and Flyover bundles pass through workflow workspaces.
No controller polls CircleCI or downloads artifacts from another CI provider.
Publication workers never restore shared PR caches.

Site jobs use fresh `main` source and read the latest complete catalog and Flyover release.
A compare-and-swap push protects the generated `gh-pages` branch.
A competing writer forces a rebuild from current inputs.
Generated commits have no parent, so image history does not accumulate on that branch.
The Pages bridge selects the latest generated commit when it starts, then reports success or failure on that exact commit.
Dispatches only wake the bridge; delayed events cannot replace pending work with an obsolete site.
Only confirmed success permits Flyover retention.
A concurrent retention request can safely encounter an already-deleted exact release ID.

Manual requests use trusted `main` for both config and checkout:

```bash
python3 -m Tools.ci_request installer --pr 295
python3 -m Tools.ci_request installer
python3 -m Tools.ci_request flyover
python3 -m Tools.ci_request pages
```

A new publication pipeline creates a new immutable build identity.
The run is an epoch-millisecond value; the attempt is the project pipeline number.
This pair sorts after historical GitHub IDs and distinguishes pipelines that start in the same millisecond.
Optional `workflowURL` metadata points new clients and the site to CircleCI.
Historical releases retain their GitHub links.
Older installed clients ignore the new field; their workflow links for new builds remain GitHub links until an app update.

Use a **new pipeline** to rebuild, including after setup or archive failure.
Rerunning all jobs reuses the old identity and workspace; it cannot replace published bytes.
A publisher retry can reuse its original verified IPA.
To recover a failed site deployment, request `pages` without rebuilding the apps.
Canceling an entire workflow cancels its failure reporters too; a saved progress state can remain until the next publication.
Individual archive failure or cancellation follows the native failure route.

## Activation and rollback

Merge requires an explicit cutover because GitHub currently requires checks from the deleted CI workflow.
Keep the existing production triggers and credentials until the replacement passes validation.

1. Authenticate the CircleCI CLI for this project. Check the registration in `project.json`.
2. Create the `github-publication` context with a dedicated GitHub credential named `GH_TOKEN`.
   Grant repository Contents read/write, Commit statuses read, and Pages read access. Do not reuse a personal developer token.
   Contents write permits release/catalog updates and `repository_dispatch`; the bridge uses its own scoped GitHub token.
3. Restrict both publication contexts to this project and this expression:

   ```text
   pipeline.config.repository.name == "kyleve/Stuff"
   and pipeline.config.ref == "refs/heads/main"
   and (pipeline.config.file_path == ".circleci/config.yml"
        or pipeline.config.file_path == ".circleci/webhook.yml")
   and pipeline.git.branch == "main"
   and not job.ssh.enabled
   and not (pipeline.config_source starts-with "api")
   ```

   Keep signing secrets only in `where-distribution-signing`.
   Never put `GH_TOKEN` in project variables or the signing context.
   Custom webhooks cannot use security-group-restricted contexts; retain project and expression restrictions.
   See [custom webhook constraints](https://circleci.com/docs/guides/orchestrate/custom-webhooks/)
   and [context restrictions](https://circleci.com/docs/guides/security/contexts/#expression-restrictions).
4. Copy enabled-app flags to CircleCI project variables: `WHERE_DISTRIBUTION_ENABLED` and `THROW_DISTRIBUTION_ENABLED`.
   Copy `INSTALLER_FEED_URL` only if the installation uses a custom feed URL.
5. Create a GitHub App pipeline definition for `.circleci/webhook.yml` in this repository.
   Add a custom webhook trigger with config and checkout branches fixed to `main`.
   Add its secret URL as a GitHub repository webhook, using JSON, SSL verification, push events, and pull-request events.
   Keep the URL secret. Do not select all event types.
6. Create a CircleCI schedule trigger on the existing definition in `project.json`.
   Use cron `23 9 * * *`, branch `main`, and parameter `publication_task=flyover`.
   CircleCI can apply a fixed delay of up to ten minutes.
   See [schedule triggers](https://circleci.com/docs/guides/orchestrate/scheduled-pipelines/).
7. Keep Pages configured for **GitHub Actions**.
   Allow `repository_dispatch` for `.github/workflows/installer-pages.yml` in the repository's Actions event policy.
8. Validate the complete CircleCI gate on this PR's exact head.
   At merge, retain required check `iOS CI - 5f599fdc` from CircleCI and remove the five retired GitHub CI checks.
   Keep the other branch-protection settings.
9. After merge, request `pages`, then an installer build, then Flyover.
   Verify live deployment, signed identity, and an installable PR's label-removal retirement.
   Remove the old `INSTALLER_CIRCLECI_TOKEN` secret and obsolete Actions variables after these checks pass.

The PR's offline checks cannot prove context permissions, webhook delivery, signing, or live Pages deployment.
Those checks belong to the activation sequence above.
For rollback, restore the previous workflows and required checks, then disable the new webhook and schedule.
Retain release assets, the catalog branch, and signing material.

## Cost estimate — 2026-11-06

This estimate covers additional CircleCI compute, before plan allowances or GitHub billing savings.
The existing iOS, signed-archive, and Flyover macOS work already runs on CircleCI.
Only the migrated checks and Linux publication work add compute.

[CircleCI's price list](https://circleci.com/pricing/price-list/) lists 200 credits/minute for `m4pro.medium`
and 10 credits/minute for the standard Docker `medium` class.
At [$0.0006 per credit](https://circleci.com/docs/guides/plans-pricing/credits/), these cost $0.12 and $0.006 per minute.

The three migrated jobs passed in [pipeline 2111](https://app.circleci.com/workflow/39723efe-cd69-42b6-b369-6cf640102b28).
Their measured executor times give this compute estimate:

| Migrated work | Runtime | Credits | Estimated cost |
| --- | ---: | ---: | ---: |
| Lint and tool checks | 2m 41s | 540 | $0.32 |
| Architecture, host, and WebKit checks | 4m 7s | 827 | $0.50 |
| Web checks and Chromium on Linux | 2m 28s | 25 | $0.02 |
| Total | | 1,392 | **$0.84 per full run** |

The WebKit step includes browser installation and tests; it took 58.5 seconds, or approximately $0.12 of the Mac job above.
All browser projects passed: 97 Chromium tests and 96 WebKit tests, with five existing skips.
CircleCI [rounds duration up to seconds, then usage up to credits](https://circleci.com/docs/reference/faq/#if-a-container-is-used-for-under-one-minute-do-i-have-to-pay-for-a-full-minute).
The table applies that rule to each job's precise API duration; displayed times and dollars are rounded.

This is one successful sample of the migrated jobs, not a long-term average or an invoice.
Cache misses, tool updates, and workload changes can increase it.
The earlier $1.75 model used six GitHub runs and overestimated the new jobs' runtime.
The [source measurements](cost-estimate.json) retain both sets of run IDs and durations.

From October 7 through November 5, GitHub recorded 1,199 CI attempts: 770 successful, 370 canceled, and 59 other outcomes.
At the measured rate, 770–1,199 full-run equivalents cost **about $640–$1,000 per month**.
Canceled/failed attempts consume partial work, and documentation-only skips reduce future usage.
This range assumes the current check workload at that historical volume; it is not an invoice forecast.

Linux publication jobs add $0.003/minute on `small` and $0.006/minute on `medium`.
For example, 1,000 five-minute medium site jobs add $30 before allowances.
Actual site time includes the Pages acknowledgement wait.
Workspace/artifact storage, plan fees, taxes, and any paid GitHub runner savings are outside this compute estimate.
The `xcode-27` GitHub runner's billing arrangement was not available, so no savings are credited.
Use more successful and canceled runs after activation to refine this estimate.
