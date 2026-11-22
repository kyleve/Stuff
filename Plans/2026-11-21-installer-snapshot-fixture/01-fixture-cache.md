# 01. Build and measure the fixture cache

Status: executing. The owner authorized the trial on November 21. Reviewed against the ordinary builder, target manifest and production fixture generator at `327b3f58e`. This experiment implements R-01 through R-03 under X-01.

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
