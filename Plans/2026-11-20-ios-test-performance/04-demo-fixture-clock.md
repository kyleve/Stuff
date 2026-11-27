# 04. Seed demo lifecycle tests in early January

Status: complete. Published in [PR 553](https://github.com/kyleve/Stuff/pull/553). The owner approved this measured change on November 20. Reviewed against main `9dd17d9b5`, including [the completed demo journal change](01-demo-journal-batch.md).

## Outcome and verification

US-04 / R-04. Keep the eleven tests of permissions, lifecycle, compatibility and log routing fast throughout the year. Each test builds a fresh standard demo through the existing model clock. The seed spans the year to date, while these assertions only need an isolated, populated world. The eleven tests took 11.207 seconds on [CI after PR 549](https://app.circleci.com/workflow/865a46d1-c504-4ec7-9956-50af96876b4b/job/8c138db7-cde0-41c7-8b4b-28b79719cf1a).

1. Supply local noon on January 1 to the model in those eleven tests. The standard demo advances to January 2 to seed its missing-day fixture. Use the same calendar as the production demo.
2. Preserve existing coverage of report contents, the demo builder’s date/category matrix, lifecycle transitions and store isolation. X-04 restricts the change to test fixtures and their existing clock injection points. The production design and APIs already support the requested behavior.
3. Run all three affected WhereUI suites and the WhereCore demo builder suite. Compare summed case times for the same eleven tests. Measure elapsed time outside Instruments.

## Execution record

In four focused runs on one Xcode 27.2 simulator, the eleven tests took 9.457 and 8.731 seconds with the original November clock and 0.757 and 0.682 seconds with the January clock. All 90 tests in the wider selection passed in every run. The mean saving was 8.375 seconds of local case time.

On a fresh iPhone 17 simulator running iOS 27.2, all 41 tests passed. The eleven changed cases totaled 0.778 seconds. The run included all 12 `DemoDataBuilderTests` and all 29 tests in the three WhereUI suites. SwiftFormat also passed for all four changed Swift files.

```sh
./test --no-generate \
  --only WhereUITests/DemoModeTests \
  --only WhereUITests/DemoModeEnvironmentTests \
  --only WhereUITests/WhereCompatibilityModelTests \
  --only WhereCoreTests/DemoDataBuilderTests
```

Reviewed implementation `a6d14b004`. Independent review traced the clock through the real demo builder and verified the eleven changed cases against the fresh simulator log. [STU-340](https://linear.app/kve/issue/STU-340)
