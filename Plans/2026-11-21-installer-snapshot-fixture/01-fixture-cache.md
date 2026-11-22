# 01. Build and measure the fixture cache

Status: executing. The owner authorized the trial on November 21. Reviewed against the ordinary builder, target manifest and production fixture generator at `327b3f58e`. This experiment implements R-01 through R-03 under X-01.

1. Measure the normal fixture. Run the production Astro generator twice and compare the full JSON, the previously built fixture, and the unchanged snapshot references.
2. On the shared iOS test builder, compute the input identity, restore one matching entry, and validate its receipt and output. On a miss, install dependencies and use the ordinary production generator. Pass the verified file into the test bundle. Test invalidation, cold and warm behavior, error recovery and the ordinary project-generation path.
3. Compare a real cold PR build and a warm PR build on distinct heads with identical fixture inputs. Record the keys, output digests, lookup, preparation, upload, snapshot build and complete workflow costs where available. Compare the applicable steps with #555 and distinguish runner variation from repeatable work. A hit should save builder time with byte-identical output and passing WebKit snapshots. If reuse fails those checks, fix the cause and repeat or retain the negative result.

## Baseline

Two local generations on the main fixture inputs took 4.439 and 3.983 seconds with site dependencies already installed. Both produced 19,340,117 bytes across twelve pages, SHA-256 `64197ba7b0c78f4cdb98ef63be54cd3ec87868ffc1759e28e51e1fa76f33dfe7`. An independently built #554 bundle had the same digest. All 24 PNG references were present locally.

The key must account for light and dark artwork named by the installer registry. The cache proof includes mutations to those bytes and generator inputs. Local work uses the same pinned tools as the ordinary renderer. The output goes through the current Xcode bundle and simulator comparison on both paths.
