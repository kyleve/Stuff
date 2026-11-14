# CI timing and cost baseline

Measured on **2026-11-06**, using UTC dates. All prices are USD.
This is a dated reference for investigating another CI provider.

Production used GitHub Actions and CircleCI at
[`main` commit `ea950e0f`](https://github.com/kyleve/Stuff/tree/ea950e0f8272750e674929d7b01f83350cff4496).
The CircleCI consolidation in [PR #484](https://github.com/kyleve/Stuff/pull/484)
was unmerged and its publication pipeline was not activated.
Its tested revision was
[`8a59f872`](https://github.com/kyleve/Stuff/tree/8a59f8728bbf12e667e47802e82c6152c8233dec).

| Scope | Cost | Evidence |
| --- | ---: | --- |
| Production native validation on CircleCI | $6.27 median | Eight successful main workflow runs |
| Production merge example, CircleCI portion | $6.87 | Usage export: native validation, signed archive, and storage |
| Complete validation after consolidation | $7.21 per full run | One successful complete run, including selection |
| Merge after consolidation | About $8; budget $7.80–$8.10 | Measured validation and archives, estimated publication and storage |

The production figures exclude GitHub's validation runner costs.
The consolidated merge estimate is additional to the PR's earlier validation runs.
None of these figures includes fixed plan fees, taxes, or failed reruns.
Plan allowances and negotiated prices can change the amount paid.

## Machines and rates

CircleCI credits are valued at **$0.0006 each**, or $15 per 25,000 credits.
The following rates were checked against the
[CircleCI price list](https://circleci.com/pricing/price-list/) and
[credit documentation](https://circleci.com/docs/guides/plans-pricing/credits/).

| CircleCI resource class | CPU | RAM | Credits/minute | USD/minute | Use |
| --- | ---: | ---: | ---: | ---: | --- |
| `m4pro.large` | 12 | 56 GB | 400 | $0.240 | Shared iOS test builder |
| `m4pro.medium` | 6 | 28 GB | 200 | $0.120 | iOS tests, snapshots, app builds, archives, Flyover; migrated lint and host checks |
| x86 Docker `small` | 1 | 2 GB | 5 | $0.003 | Workflow selection and lightweight preparation |
| x86 Docker `medium` | 2 | 4 GB | 10 | $0.006 | Migrated web checks and publication |

The measured CircleCI Mac jobs used Xcode 27.2. Linux jobs used
`cimg/python:3.12`. These describe the measurement environment; current pins
remain in the repository configuration.

Production GitHub validation used the custom `xcode-27` runner label.
Its CPU, RAM, and exact billing SKU were not established during this investigation.
Its cost must remain unknown until account billing confirms those details.
The retained Pages deployment uses standard `ubuntu-latest` in this public repository.
Its runner compute is free under
[GitHub's public-repository billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

## Measured complete validation after consolidation

[CircleCI pipeline 2112](https://app.circleci.com/workflow/0c1fe8ea-79eb-42bc-b83d-424467ea1529)
passed all seven validation jobs at `8a59f872`.
The workflow took **12m 01s**. From selection starting to validation finishing,
elapsed time was about **12m 14s**.

Times below are job elapsed times, rounded to the nearest second.
Credits cover all workers in each job. Dollar values retain four decimal places
so the total can be reproduced.

| Job | Job number | Machine | Workers | Elapsed | Credits | USD |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| Build iOS Tests | 3734 | `m4pro.large` | 1 | 3m 33s | 1,424 | $0.8544 |
| Snapshot Tests (iOS) | 3735 | `m4pro.medium` | 5 | 8m 07s | 6,206 | $3.7236 |
| Build & Test (iOS) | 3736 | `m4pro.medium` | 1 | 5m 47s | 1,158 | $0.6948 |
| Lint and Tool Tests | 3737 | `m4pro.medium` | 1 | 2m 42s | 540 | $0.3240 |
| Build Where Audiences | 3738 | `m4pro.medium` | 2 | 4m 30s | 1,690 | $1.0140 |
| Architecture and macOS Tests | 3739 | `m4pro.medium` | 1 | 4m 53s | 978 | $0.5868 |
| Web Checks and Tests | 3740 | Docker `medium` | 1 | 2m 39s | 27 | $0.0162 |
| Validation subtotal | | | | | **12,023** | **$7.2138** |
| Select workflows | 3733 | Docker `small` | 1 | About 10s | 1 | $0.0006 |
| Total compute | | | | | **12,024** | **$7.2144** |

The large Mac builds both test schemes once. Unit and snapshot workers attach
those products and run without compilation. Two additional workers build Where
Beta and Where App Store. See the
[measured job configuration](https://github.com/kyleve/Stuff/blob/8a59f8728bbf12e667e47802e82c6152c8233dec/.circleci/jobs.yml).

Snapshots account for **51.6%** of validation compute cost.
Four snapshot workers ran for roughly seven to eight minutes each.
The fifth, reserved for newly added suites, had no assigned suites and exited
after about nine seconds. Multiplying the slowest worker's time by five would
overstate its cost.

Web tests are a small part of the total. The WebKit step took about 75 seconds
on the Mac host worker, including browser installation: approximately **$0.15**.
The entire Linux web job cost **$0.0162**. Together, these represent about **$0.17**,
or 2–3% of validation compute. This excludes shared Mac setup time.

The browser suite reported 193 passes and five existing skips across Chromium
and WebKit, each with desktop, portrait, and landscape projects.
WebKit remained on macOS after Linux runs stalled during high-density atlas rendering.
The passing configuration retained the existing assertions and timeouts.

### Incremental cost of moving GitHub validation

The three migrated jobs are lint/tools, architecture/host/WebKit, and Linux web.
They cost **$0.9270** in pipeline 2112.
The same three jobs cost **$0.8352** in
[pipeline 2111](https://app.circleci.com/workflow/39723efe-cd69-42b6-b369-6cf640102b28).
Only those three jobs completed there; downstream native jobs were canceled.

Thus, the measured addition to CircleCI validation compute is **$0.84–$0.93 per
full run**. This excludes publication and any savings from GitHub billing.
It supersedes the earlier $1.75 estimate derived from GitHub durations.

## Production baseline before consolidation

Between November 2 and November 6, eight successful main validation workflows
had median compute usage of 10,446.5 credits: **$6.2679**.
Their costs ranged from **$6.0636 to $6.4764**, with median elapsed time **13m 04s**.
These workflows covered native work only; GitHub ran the remaining validation.
The [latest sampled native workflow](https://app.circleci.com/workflow/6ad48156-1648-440a-9edc-c8065f4d7f49)
used 10,172 credits, or $6.1032.

Seven successful signed archives in that window had median compute usage of
730 credits: **$0.4380**. Their costs ranged from **$0.3960 to $0.5028**.
Median workflow elapsed time was **3m 46s**.
The [latest sampled archive](https://app.circleci.com/workflow/fcf7bbf0-c82a-4752-843a-43b17caff946)
used 838 credits, or $0.5028.

Six successful GitHub validation attempts gave these median job times:

| GitHub job, all using `xcode-27` | Median elapsed |
| --- | ---: |
| Lint & Formatting | 1m 56s |
| Tool Tests | 4m 25s |
| Bumper Bowling | 3m 36s |
| Build & Test (macOS) | 4m 16s |
| Web Checks & Tests | 7m 11s |

The [saved timing samples](https://github.com/kyleve/Stuff/blob/8a59f8728bbf12e667e47802e82c6152c8233dec/.circleci/cost-estimate.json)
contain all six run URLs and individual durations.
These jobs overlap, so their times do not sum to PR turnaround time.
Different commits, machines, caches, and job grouping prevent a controlled speed comparison.

Production configuration at the measurement revision:
[GitHub validation](https://github.com/kyleve/Stuff/blob/ea950e0f8272750e674929d7b01f83350cff4496/.github/workflows/ci.yml),
[CircleCI jobs](https://github.com/kyleve/Stuff/blob/ea950e0f8272750e674929d7b01f83350cff4496/.circleci/continue.yml).

## What a merge costs

### Recorded production usage

The November 4 merge of [PR #474](https://github.com/kyleve/Stuff/pull/474),
commit `a22b6095`, provides a concrete example from CircleCI's usage export:

| Work | Pipeline | Compute credits | Storage credits | Total credits | USD |
| --- | ---: | ---: | ---: | ---: | ---: |
| [Native validation](https://app.circleci.com/workflow/57ef23c1-c34d-449e-ba09-92eba9d83a6a) | 1991 | 10,528 | 89 | 10,617 | $6.3702 |
| [Where signed archive](https://app.circleci.com/workflow/560b868f-2cc3-42e0-a5e6-64df606352c3) | 1992 | 798 | 33 | 831 | $0.4986 |
| Total | | **11,326** | **122** | **11,448** | **$6.8688** |

Storage contributed **$0.0732**. The matched records had no network or Docker
layer caching charges. This is the CircleCI portion of that production merge;
GitHub validation costs remain unmeasured.

### Forecast after consolidation

The tested migration would repeat full validation after a merge.
It would also run publication work associated with main and the closed PR.

| Work per healthy merge | USD | Basis |
| --- | ---: | --- |
| Complete validation, including selection | $7.2144 | Pipeline 2112 |
| One Where Development signed archive | $0.40–$0.50 | Seven successful production archives |
| Linux publication, site updates, and PR retirement | $0.10–$0.25 | Estimate from existing site timings and proposed job graph |
| Storage | $0.07–$0.10 | Recorded $0.0732 example, with allowance for additional artifacts |
| GitHub Pages runner compute | $0 | Standard Ubuntu runner in a public repository |
| Planning total | **$7.80–$8.10** | Rounded budget range |

Publication was not activated, so its Linux cost and extra storage remain forecasts.
The total assumes one successful run and the current app set.
Both app distribution flags were enabled, but Throw's source was absent.
Consequently, main produced only a Where archive.

The [proposed publication graph](https://github.com/kyleve/Stuff/blob/8a59f8728bbf12e667e47802e82c6152c8233dec/Tools/ci_publication.py)
can request six site updates around a normal same-repository merge.
Main requests progress, completion, and an independent site update.
Closing the PR requests Where retirement, Throw retirement, and another site update.
Retirement can run even when an app's source is absent.
Concurrent updates can supersede one another, so six is a potential count.

Existing GitHub site runs illustrate the timing uncertainty:

| Site run | Deployment job | Pages deployment step |
| --- | ---: | ---: |
| [42270303433](https://github.com/kyleve/Stuff/actions/runs/42270303433) | 1m 51s | 28s |
| [42264460159](https://github.com/kyleve/Stuff/actions/runs/42264460159) | 7m 24s | 6m 04s |

Dependency installation took about 37–38 seconds in both examples.
Most of the difference came from waiting for Pages.
The proposed CircleCI publisher waits for deployment acknowledgement for up to
ten minutes, charging Linux time while it waits.

### Daily work outside merge costs

Flyover runs daily or manually; it is not triggered by every merge.
The [November 5 sample](https://app.circleci.com/workflow/86540a60-cc3d-4b25-85cd-034a9f510d1a)
ran on `m4pro.medium` for **14m 43s**.
Its export used 2,944 compute credits and 147 storage credits:
**$1.8546 total**. This excludes its separate publication and site jobs.

## Run frequency and comparison limits

Under the consolidated scenario, one full PR validation costs about **$7.21**
in compute. Three full validations cost about **$21.64**.
Adding an approximately $8 merge gives about **$15.20** or **$29.60**, respectively.
PR storage and optional `installable` publication add to those examples.
Canceled runs consume the work completed before cancellation.

Eligible Markdown-only PRs skip expensive validation on both existing providers.
Main pushes still run full validation, including after a Markdown-only merge.
The documented [CI selection contract](Tools/AGENTS.md#ci-selection) owns eligibility.

The October 7–November 5 GitHub sample contained 1,199 CI attempts:
770 successful, 370 canceled, and 59 with other outcomes.
These are attempts across PRs and main, not unique PRs or full-run equivalents.
They exclude separate archive and site workflows.
Multiplying 1,199 by a full-run price would overstate validation usage.

CircleCI Insights supplies compute credits and elapsed times.
The [API documentation](https://circleci.com/docs/api/v2/) distinguishes Insights
from billing data; the usage export is the stronger billing evidence.
The export requested through November 6 contained only November 4–5 data when
retrieved. The final migration run therefore has compute measurements, but no
complete usage export yet.

For runtime estimates, CircleCI rounds duration up to the next second, then
rounds credits up. Parallel workers contribute their own runtime.
See the [billing rounding FAQ](https://circleci.com/docs/reference/faq/#if-a-container-is-used-for-under-one-minute-do-i-have-to-pay-for-a-full-minute).
Reported credits are preferable to multiplying job elapsed time by parallelism.

A provider comparison needs the same commit, test coverage, cache conditions,
toolchain, and artifact handoff. Relevant capabilities include:

- Apple Silicon macOS with the pinned Xcode and iOS Simulator runtime.
- Shared compiled test products, parallel snapshot workers, and Git LFS references.
- Both browser engines and all viewport projects, including macOS WebKit behavior.
- Signed archives with isolated signing credentials and trusted publication code.
- Workspaces, caches, artifacts, retention, transfer costs, and concurrency limits.
- Required PR checks, cancellation, API failure reporting, and deployment acknowledgement.

The complete migrated validation is one successful sample, not a long-term median.
Queue delay, cache misses, retries, additional apps, and provider-specific fixed
fees can change both turnaround time and total cost.
