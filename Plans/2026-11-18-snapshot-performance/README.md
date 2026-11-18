# Snapshot performance after comparison overlap

## Planning checkpoint

On November 18 the repository owner requested a fresh performance investigation, a plan, and execution. PR 529 (`4f5b9d520`) supplies the starting code and the retained full local control. Its Swift implementation matches PR 528. Both deliverables are complete and published for review in [PR 530](https://github.com/kyleve/Stuff/pull/530). Full local and CI verification passed. The existing investigation is tracked by [STU-121](https://linear.app/kve/issue/STU-121).

## Outcome and scope

Reduce the time maintainers wait for a verified snapshot run. Preserve all approved images, configurations, readiness guarantees and failure diagnostics. Record elapsed test time separately from summed capture work. Candidate selection and implementation are delegated by the request.

## Discovery and decisions

[PR 524](https://github.com/kyleve/Stuff/pull/524) added settle traces. [PR 525](https://github.com/kyleve/Stuff/pull/525) removed redundant fixture settling. [PR 528](https://github.com/kyleve/Stuff/pull/528) overlapped bounded comparison with the next capture. [PR 529](https://github.com/kyleve/Stuff/pull/529) found a combined 860.623 → 805.560 seconds locally, with 935 captures, 78 functions and zero retries. Its follow-ups retained the existing PNG processing, comparison cap and cadence. The isolated PR 528 CI pair ran in 464.843 and 484.093 seconds respectively. The local improvement has yet to translate into a demonstrated CI wall-time gain.

| Opportunity | Observation | Decision |
| --- | --- | --- |
| Describe differences faster | In the retained PR 529 candidate, 150 byte-different references triggered a scalar walk across 806,324,211 normalized pixels, of which 20,799,209 differed in RGB. The earlier 110-capture profile attributed 16.094s to diagnostics. | Measure exact equality of contiguous pixel spans before calculating RGB deltas. Works for ordinary images and composed sheets. |
| Fetch fewer references per CI worker | Four workers each requested 877 references (812.5 MiB of logical file sizes). Their assignments used 257.2, 233.0, 127.8 and 194.5 MiB. Hydration took 19.3–54.6s per active worker across the PR 528 pair. | Fetch and verify the assigned paths with the existing shard command. Measure logical bytes and elapsed time separately. [STU-146](https://linear.app/kve/issue/STU-146) tracks a separate warm-cache experiment. |
| Authoritative comparison of identical PNGs | In the local run, the 727 ordinary captures without a reported difference accumulated 25.772s of comparison, some already overlapped. | Retain structural validation, panel checks and recording precedence. The earlier byte-equality experiment and its remeasurement criteria are recorded in [STU-124](https://linear.app/kve/issue/STU-124). |
| WebKit and native fixture readiness | The 24 installer captures spent 50.957s in the measurement hook. Forty standalone calendar month and badge captures spent 10.917s in final settling without an observed change. The initial-position screen did change during settling. | Reusing pages or shortening readiness changes the evidence required to trust a capture. Keep the existing readiness investigation in [STU-121](https://linear.app/kve/issue/STU-121). |

## Stories, requirements and exclusions

| Story | Requirement | Deliverable |
| --- | --- | --- |
| US-01. A developer wants a quicker explanation of a snapshot difference. | R-01. Preserve every reported count, maximum RGB delta, and top-left bounding rectangle. Measure the diagnostic and representative test bodies. | [01 — Review diagnostics](01-review-diagnostics.md) |
| US-02. A reviewer wants CI to spend less time fetching unused images. | R-02. Fetch and verify the references needed by each assigned suite, including intake and nested paths. Quantify the reduction. | [02 — Shard reference downloads](02-shard-references.md) |
| Both stories | R-03. Keep every test, reference, verdict, tolerance, retry and trace. Preserve clean failure handling. | Both plans |

X-01 excludes changes to rendering, scheduling and fixture readiness. X-02 excludes changes to shard count, suite assignments and test selection. These boundaries let each experiment change one cost.

## Horizon and review

Both numbered plans are in the current horizon and have independent code paths. Their diagrams and implementation sketches are in the linked files. Q-01 (closed, November 18) asked which local cost could be reduced without changing an assertion. The diagnostic runs after capture and its scalar implementation supplies an exact oracle. Q-02 (closed, November 18) asked how CI could request less data without weakening coverage. The source inventory and existing reference resolver identify each suite directory, including suites with no images. Both decisions are integrated into the requirements, steps and acceptance checks.

Reviewed November 18 at `4f5b9d520`. The review identified two pitfalls now covered in acceptance: alpha-only differences in RGBA spans and an empty LFS include list meaning an unrestricted fetch. Repository code, local artifacts and the paired CI jobs supply the necessary evidence. Mermaid diagrams were checked as source. Both plans passed readiness review before implementation at `f6e69a177`. Benchmark noise can limit elapsed-time conclusions.

## Outcome and delivery

The full local review run fell from **805.560s to 757.995s** (47.565s, 5.90%). All 935 captures and 78 functions passed with zero retries. The CI workers fetched 75% fewer cold LFS object bytes. Per-worker hydration fell from **20.842–28.529s to 5.817–7.763s**. The complete snapshot job took **556.963s before and 484.078s after**. One control worker had a recovered timeout and a slow checkout. Use the per-step numbers when attributing the observed improvement. [Local results](01-review-diagnostics.md) · [CI pair](02-shard-references.md#ci-verification)

The root coordinated both plans on `perf/snapshot-fresh-look`, ran the hosted tests serially and published [PR 530](https://github.com/kyleve/Stuff/pull/530) above PR 529. Renderer and shard-tooling workers delivered implementation and replay evidence to the root. Independent review checked the complete diff through `99406503c`, the fixed-input replay and all eight CI JUnit files. Review clarified the exceptional LFS fallback and the scope of zero-RGB reports. Full-run body-duration analysis sums the individual executions of parameterized tests using the repository's result reader.

The [control](https://app.circleci.com/workflow/2da703c7-3b59-44e8-a524-33c58bcb3a97) and [candidate](https://app.circleci.com/workflow/df6d565c-6c0f-450f-a067-ce45ea4fd1f5) full workflows passed. The candidate tested `62984d360`; its runtime and tooling match `99406503c`. All six [GitHub CI gates](https://github.com/kyleve/Stuff/actions/runs/44308617386) passed on the same Git tree. Both numbered plans are complete. STU-121 links back to this plan and remains In Review while the PR is open.
