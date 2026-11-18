# 01 — Skip unchanged pixels when describing a difference

- Status: complete
- Dependencies: none. [Overview and scope](README.md)

## Deliverable and design

Implement R-01 and R-03 in `SnapshotReferenceDiff.swift`. The existing review path decodes both PNGs into the same packed RGBA layout. Swift calculates three channel differences, count, maximum and bounds for every pixel even when large portions are identical. Compare contiguous bytes first. Unequal spans still use the original RGB rules, including ignoring alpha. Keep allocation, coordinate origin and the reporting wire format intact.

```mermaid
flowchart LR
    A[Normalized capture and reference] --> B{Equal byte span?}
    B -->|Yes| D[Advance]
    B -->|No| C[Accumulate exact RGB differences]
    C --> D
    D --> E[Existing magnitude report]
```

Swift sketch inside the existing magnitude calculation, with pointer lifetime and row boundaries omitted:

```swift
if bytesDiffer(captureSpan, referenceSpan) {
    accumulateRGBDifferences(in: span)
}
```

## Steps and acceptance

1. Replay retained production-size captured and approved PNGs against the original scalar operation and candidate. Compare the complete magnitude per pair. Include equality, sparse and widespread change, alpha-only change, partial spans and boundaries in verification. Keep the simpler competitive implementation.
2. Exercise the public comparison path with Swift Testing. Run `./test --only SnapshotKitTestingTests/SnapshotReferenceDiffTests` and the focused RegionSummaryCard, EstimatedTimeFeaturesView and WhereLifecycleFailureView snapshot suites with `--review --timings --record never` before and after. Keep build and simulator preparation separate from test elapsed.
3. Adopt if replay agrees exactly and runtime savings reproduce on representative inputs. Run all snapshots once on the adopted change and compare counts, IDs and capture geometry against the retained PR 529 baseline. Report elapsed and summed work separately. Limit the strength of any full-suite speed claim to the available pairs.
4. Retain the measured results and independent review in the plan. If results diverge, keep the scalar implementation and record the mismatching case. Temporary benchmarks and raw logs stay outside Git.

## Progress and resume point

The implemented fast path compares one complete normalized RGBA row with `memcmp` and applies the scalar RGB calculation on every unequal row. The focused simulator build passed all eight `SnapshotReferenceDiffTests` functions, including an odd-width image, its last pixel, a full-image change, and an alpha-only change. SwiftFormat and whitespace checks passed.

A macOS Swift debug replay compared the parent and candidate magnitude functions on the same decoded inputs, alternating their order per image. The 93 ordinary captured/reference pairs from the retained PR 528 run contained 597,279,951 pixels. All 93 complete magnitudes matched, including counts, maximum channel differences and bounds from the historical reports. Summed scan time fell from 76.992s to 6.799s (91.2%). Image decoding and normalization took another 6.253s outside the scans. The replay shared the machine with a framework build. These are isolated diagnostic timings.

The three focused suites passed before and after. Their test bodies fell from 65.425s to 52.354s (20.0%). The runner test phase fell from 81.091s to 64.622s. All 77 capture identities, 215,727,762 pixels, 85 tiles and 149 settle calls matched, with zero retries. Forty-four of 45 diagnostic reports matched exactly across the live captures. One additional sheet in each run had different PNG bytes and zero differing normalized RGB pixels. The retained fixed-input replay above isolates algorithm equivalence from live capture variability.

A full `./test --snapshots --no-generate --review --timings --record never` run on Xcode 27.2 passed all 935 captures and 78 functions. Compared with the retained PR 529 run at `05bb537a1` (identical implementation to `4f5b9d520`), test elapsed fell from **805.560s to 757.995s**, saving **47.565s (5.90%)**. Summed instrumented comparison work fell from 103.120s to 49.726s. Background overlap and cutsheet work outside individual capture timings prevent treating this summed work as elapsed time.

The full runs matched on the multiset of capture identities, 4,797,647,739 pixels, 1,014 tiles, and all 1,818 settle policies and outcomes. Both had zero retries. Of the 150 control and 151 candidate review rows, 145 matched exactly, counting duplicate reports separately. Both live runs passed their approved references. The 93-pair fixed-input replay owns the exact diagnostic equivalence check. The full local comparison uses one run per revision on the same Mac with different checkout-owned simulators. The measured improvement applies to runs that enable review diagnostics.

Across the [paired CI runs](02-shard-references.md#ci-verification), ordinary captures accumulated 174.848s of comparison work in the control and 91.136s in the candidate (47.9% less). Summed test phases fell from 1,282.131s to 1,206.366s across four active workers. The full pair includes both implemented changes.

## Outcome

Complete in [PR 530](https://github.com/kyleve/Stuff/pull/530). Independent review reproduced the local and CI measurements. No implementation steps remain.
