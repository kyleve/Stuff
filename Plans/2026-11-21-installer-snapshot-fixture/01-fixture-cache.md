# 01. Build and measure the fixture cache

Status: complete. [PR #557](https://github.com/kyleve/Stuff/pull/557) delivers R-01 through R-03 under X-01. The owner authorized the trial on November 21. Review covered the ordinary builder, target manifest and production fixture generator at `327b3f58e`.

1. Measure the normal fixture. Run the production Astro generator twice and compare the full JSON, the previously built fixture, and the unchanged snapshot references.
2. On the shared iOS test builder, compute the input identity, restore one matching entry, and validate its receipt and output. On a miss, install dependencies and use the ordinary production generator. Pass the verified file into the test bundle. Test invalidation, cold and warm behavior, error recovery and the ordinary project-generation path.
3. Compare a real cold PR build and a warm PR build on distinct heads with identical fixture inputs. Record the keys, output digests, lookup, preparation, upload, snapshot build and complete workflow costs where available. Compare the applicable steps with #555 and distinguish runner variation from repeatable work. A hit should save builder time with byte-identical output and passing WebKit snapshots. If reuse fails those checks, fix the cause and repeat or retain the negative result.

## Baseline

Two local generations on the main fixture inputs took 4.439 and 3.983 seconds with site dependencies already installed. Both produced 19,340,117 bytes across twelve pages, SHA-256 `64197ba7b0c78f4cdb98ef63be54cd3ec87868ffc1759e28e51e1fa76f33dfe7`. An independently built #554 bundle had the same digest. All 24 PNG references were present locally.

The key must account for light and dark artwork named by the installer registry. The cache proof includes mutations to those bytes and generator inputs. Local work uses the same pinned tools as the ordinary renderer. The output goes through the current Xcode bundle and simulator comparison on both paths.

## Implementation and local verification

The iOS test builder opts into a Tuist build phase that copies the verified JSON into the original test bundle. Every active snapshot worker receives the compiled bundle through the existing workspace. The helper validates an input fingerprint, output SHA-256 and byte count. It installs dependencies on a miss and publishes the new receipt after a complete render.

A review found that otherwise identical checkouts could fingerprint different Python bytecode files. The corrected key enumerates tracked files and hashes their bytes, plus the two artwork paths from the registry. A regression test moves a restored entry to another checkout with different untracked bytecode and forbids npm. Adding a new tracked input changes the key. Missing, stale or damaged entries regenerate. CircleCI cache entries are immutable. A persistently damaged remote entry will regenerate locally on subsequent runs until it expires or the cache namespace changes.

Both local Xcode builds ran the real installer WebKit suite. Each exercised all 24 existing references on iOS 27.2. The normal build had 20 byte-identical images and four differences of at most 1/255 on one channel. The cache build produced 24 byte-identical images. Both bundles contained the historical fixture digest. The warm build log confirms that Xcode ran the copy phase and replaced its destination.

The final tracked-input implementation took 8.065 seconds locally on a fixture miss with a warm npm download cache, then 0.088 seconds on a JSON hit. Both invocations returned the original fixture digest. CircleCI measurements own the production decision because local timings exclude remote cache transfer.

## CircleCI trial

The first ordinary PR build used the full production builder on the large Mac. Fingerprinting took 0.405 seconds, the unsuccessful restore 0.379 seconds, npm and rendering 34.414 seconds, and saving the new entry 0.677 seconds. Together these steps took **35.875 seconds**. The zstd upload was 3.4 MiB. The generated fixture matched the local baseline's SHA-256 and byte count. The CI input fingerprint was `ba70b6cf27fb9498bc8ad26f93bf55cab5d777ec18fba292cd8671ce0c501246`. [Cold build #5036](https://app.circleci.com/workflow/19ab3f24-001b-465c-8483-8e6ab67568a4/job/6b37ed11-f9fc-4e43-b24c-a6ffec530a99)

The cold snapshot scheme took 11.575 seconds to build. The ordinary #555 builder took 28.720 seconds installing npm dependencies and 15.653 seconds on that scheme. Summing those boundaries gives 44.373 seconds on #555 and 47.450 seconds on the cold trial, a 3.077-second increase (about 21 large-Mac credits at the nominal rate). The compiled workspace had the same reported size of 1,453,637,632 bytes. The `Project.swift` change also triggers snapshot inventory validation on both PR heads. That cost is separate from fixture preparation.

A fresh Mac on the same Xcode 27.2 image restored the actual #5036 cache, with identical source inputs and fixture bytes. Fingerprinting took 0.500 seconds, restoring 0.918 seconds, and the verification step 0.511 seconds, for **1.929 seconds**. The helper itself ran for 0.107 seconds. That probe covered the real CircleCI cache transfer and excluded Xcode build, save and simulator steps. Its sole code difference was the one-off workflow entry point. [Remote warm probe #5039](https://app.circleci.com/workflow/b61de2b1-56eb-4baa-a16a-f99b63c48033/job/4af30fe7-c1f9-4d19-90e0-d82583248689)

Replaying the implementation's actual file paths, including workspace manifests and registered artwork on each side of each diff, found unchanged source inputs on 58 of 89 otherwise-paid final diffs and 45 of 68 paid earlier heads in the [selection study](https://github.com/kyleve/Stuff/pull/556). Unchanged source inputs model an opportunity to hit a warm entry. Runner image changes, cache expiry and eviction can still cause misses.

All 17 applicable checks passed on the cold head. The installer WebKit test exercised all 24 references. The 22 captures that reported a pixel difference had exactly the same counts, bounds and maximum one-channel-level difference as #555.

The [implementation PR](https://github.com/kyleve/Stuff/pull/557) records the final ordinary warm builder and end-to-end CI measurements. Its second head changes the experiment record and cost documentation, with the same cache inputs as the first.
