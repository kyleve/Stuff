# Snapshot performance after comparison overlap

## Planning checkpoint

On November 18 the repository owner requested a fresh performance investigation, a plan, and execution. PR 529 (`4f5b9d520`) supplies the starting code and the retained full local control. Its Swift implementation matches PR 528. Both independent deliverables are executing. The root is comparing focused local runs and collecting a fresh CI control. The existing investigation is tracked by [STU-121](https://linear.app/kve/issue/STU-121).

## Outcome and scope

Reduce the time maintainers wait for a verified snapshot run. Preserve all approved images, configurations, readiness guarantees and failure diagnostics. Record elapsed test time separately from summed capture work. Candidate selection and implementation are delegated by the request.

## Discovery and decisions

[PR 524](https://github.com/kyleve/Stuff/pull/524) added settle traces. [PR 525](https://github.com/kyleve/Stuff/pull/525) removed redundant fixture settling. [PR 528](https://github.com/kyleve/Stuff/pull/528) overlapped bounded comparison with the next capture. [PR 529](https://github.com/kyleve/Stuff/pull/529) found a combined 860.623 → 805.560 seconds locally, with 935 captures, 78 functions and zero retries. Its follow-ups retained the existing PNG processing, comparison cap and cadence. The isolated PR 528 CI pair ran in 464.843 and 484.093 seconds respectively. The local improvement has yet to translate into a demonstrated CI wall-time gain.

| Opportunity | Observation | Decision |
| --- | --- | --- |
| Describe differences faster | In the retained PR 529 candidate, 150 byte-different references triggered a scalar walk across 806,324,211 normalized pixels, of which 20,799,209 differed in RGB. The earlier 110-capture profile attributed 16.094s to diagnostics. | Measure exact equality of contiguous pixel spans before calculating RGB deltas. Works for ordinary images and composed sheets. |
| Fetch fewer references per CI worker | Four workers each requested 877 references (812.5 MiB of logical file sizes). Their assignments used 257.2, 233.0, 127.8 and 194.5 MiB. Hydration took 19.3–54.6s per active worker across the PR 528 pair. | Fetch and verify the assigned paths with the existing shard command. Measure logical bytes and elapsed time separately. [STU-146](https://linear.app/kve/issue/STU-146) tracks a separate warm-cache experiment. |
| Authoritative comparison of identical PNGs | In the local run, the 727 ordinary captures without a reported difference accumulated 25.772s of comparison, some already overlapped. | Retain structural validation, panel checks and recording precedence. The earlier byte-equality experiment and its remeasurement criteria are recorded in [STU-124](https://linear.app/kve/issue/STU-124). |
| WebKit and native fixture readiness | The 24 installer captures spent 50.957s in the measurement hook. The focused Calendar fixtures also pay final settling. | Reusing pages or shortening readiness changes the evidence required to trust a capture. Keep the existing readiness investigation in [STU-121](https://linear.app/kve/issue/STU-121). |

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

## Execution checkpoint

The root owns verification, publication, Linear linkage and reporting. Renderer and suite-tooling workers own plans 01 and 02 respectively in this worktree on `perf/snapshot-fresh-look`. Each returns changed paths, verification, remaining work and blockers to the root. The root runs the simulator serially and checks the complete diff. Independent review of the complete diff through `99406503c` found no code blockers. It clarified the fallback for LFS directory patterns and the scope of a zero-RGB report. All 77 focused capture identities matched and the eight diagnostic test functions passed. The full local suite and fresh CI control are running. The next step is to publish above PR 529 and collect the candidate CI run.
