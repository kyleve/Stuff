# 05. Share a library test host in full iOS runs

Status: executing. Reviewed against main `3d33d33f6` on November 21. The owner selected a paired CI trial after reviewing the prototype and its process isolation trade-off. [STU-342](https://linear.app/kve/issue/STU-342)

## Outcome

US-05 / R-05. A full iOS validation runs the same cases with fewer test-host launches. Developers can still select one module, suite or case through `./test`, including with compiled artifacts. Test results retain the owning module for timing history and retries. X-05 limits grouping to the twelve measured library modules. App-host tests, the snapshot renderer regression bundle and image snapshot workers retain their isolation.

## Implementation and verification

1. Build one full-run target from the twelve original targets' sources, resources and links. Keep standalone targets and their focused selectors. Verify shared build artifacts, filtered reruns and real module-level report identity.
2. Run the complete unit action on main and on the branch with the same simulator runtime. Compare test identifiers, parameterized results, skips and expected failures. Exercise several serial execution orders in the grouped host, check the observed orders, and investigate any failures. Preserve the host window and shared state for the next test.
3. Compare a clean CircleCI builder, workspace handoff, unit worker and compute credits against main at the same Xcode and resource classes. Report queue or environment differences separately. Check the normal PR gate and publish the results in the implementation PR.

## Prototype and control

On the earlier `9dd17d9b5` experiment, twelve independent hosts took 46.83 and 47.61 seconds for 922 tests in 147 suites. Two grouped runs took 12.48 and 12.42 seconds. The full action took 303.91 seconds on the restored project and 271.48 seconds with grouping. All 3,009 results matched. A successful full CI validation exists at the trial's exact parent. [Main control](https://app.circleci.com/workflow/6c61ffb3-475e-4ead-89f5-959d43ffb223)

The target, runner and reporting changes share one branch. The primary agent owns integration, state isolation checks, independent review and CI measurement.

## Implementation and local results

[PR 554](https://github.com/kyleve/Stuff/pull/554) uses one serial test target built from the existing owners' sources, package dependencies and resources. Full artifacts include the mapping of 147 suites to twelve original modules. Named and diff-selected runs use the original targets. A review found that the failure summary widened a slash-nested suite selector; the corrected selector retains the nested path and has focused regression coverage.

On November 21, the main and grouped full Xcode actions took 262.615 and 247.142 seconds on the same booted iPhone 17 / iOS 27.2 simulator. All 3,009 identifiers and JUnit outcomes matched across 513 suites. Both Xcode results contain 3,003 passes, four expected failures and two skips. The real full-build artifact reran a whole module, a grouped suite with a JSON resource and an ungrouped WhereUI suite together, passing all 35 selected tests.

The ordinary serial runner repeated the same 147-suite order even with Xcode random ordering requested. The shipping scheme uses the ordinary ordering. A dedicated CI probe compiles byte-identical copies of the tests with two seeded source-file orders. It checks case and parameter parity, actual chronological suite order, and failures in all three runs. The paired production CI result and separate order verification are recorded in the PR.

The first clean CI builder failed to infer the inherited `Encodable` conformance of the Periscope macro fixture when compiling `LogAttachmentTests` in the larger module. Declaring `Codable` directly on that test event preserves its production macro and the original attachment round-trip assertion. Replaying the same 13-file compiler batch reproduced both diagnostics with the original fixture and succeeded with the explicit conformance. The rebuilt grouped target passed all 922 cases locally. [Initial compiler diagnostic](https://app.circleci.com/workflow/4b6bd235-ec88-4872-8f4c-2fdb35c20ec5/job/d2769107-8c35-402a-8eed-f1c7fd75f7fe)
