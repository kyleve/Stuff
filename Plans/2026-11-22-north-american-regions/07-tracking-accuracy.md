# 07. Tracking accuracy across sources

- Status: complete
- Depends on [06. Tracking and display boundaries](06-tracking-and-display-boundaries.md).
- Delivers [R-08](README.md#requirements) for S-01 and S-03 under [Q-08](README.md#questions-and-resolutions). [Implementation PR #563](https://github.com/kyleve/Stuff/pull/563).

## Decision and baseline

Plan 06 kept Canadian tracking at publisher resolution and certified US tracking against TIGER/Line. On November 25 the owner selected the same selective restoration and 25 m maximum displacement for every publisher-backed tracking source.

In a Canadian prototype, restoring vertices after a 45 m simplification reduced the 13 tracking files from 920,589 to 428,642 bytes. The greatest verified upper bound was 23.998 m relative to the previously bundled Canadian geometry. That reference already included coordinate rounding and a repair to six Ontario vertices. The release must also account for those changes relative to the original Statistics Canada boundaries.

## Implementation

1. Run every tracking adapter through the same simplification, restoration and verification steps. Restore detail where a simplified edge departs too far from its source. Preserve both owners of each shared edge, every island and every hole.
2. Certify the final decoded TWKB against the original publisher coordinates in both directions along continuous edges. Include the effects of topology repair and rounding. Bind the upper bound, the tracking input hashes and the encoded output hash to the region. Refuse a candidate with missing coverage or an upper bound above 25 m.
3. Generate and adopt the Canadian release through the [RegionKit updater](../../Where/RegionKit/README.md#regenerating). Geographic IDs, tracking consumers, display geometry and the existing hand-drawn EU file retain their plan 06 contracts. The change is confined to the maintainer toolchain and region resources and needs no new Swift interface.

## Verification

- Compare a Canadian bend and both sides of a shared border against source geometry. Exercise the Ontario repair, rounding and a malformed or incomplete accuracy report. Require the same continuous bound on each Canadian and US tracking region.
- Refresh from the pinned source vintages, replay from the download cache, and compare the two candidates. Adopt with the public CLI and run its offline check. Confirm the US tracking files, display files and EU resource match plan 06 byte for byte.
- Record shipped Canadian and US tracking sizes, the certified upper bounds and source-to-output membership results. Run the Python and Ruby updater tests and the affected iOS tracking tests. If verification fails, retain the previous release or replay it from the revision that generated it.

## Execution evidence

The live refresh and offline replay of all 47 publisher inputs produced byte-identical format-4 candidates. The public updater adopted the release and regenerated the bundled files offline. All 65 generated tracking files have certificates. Both roles matched their sources at all 193 geographic probes.

| Tracking | Subdivisions | Encoded bytes | Maximum certified displacement |
| --- | ---: | ---: | ---: |
| US | 52 | 708,466 | 24.000 m |
| Canada | 13 | 357,139 | 24.008 m |

Canada uses 65,886 vertices and saves 563,450 bytes (61.2%) over plan 06. An independent decoder and continuous-distance check verified all 13 files against the full-precision StatCan downloads. At the marked Ontario–Nunavut bend (54.9925516° N, 82.2667869° W), the initial simplification put the nearest edge 167.27 m from the source vertex. Restoration reduced that distance to 4.25 m. The US tracking files, display files and shared EU geometry match plan 06 byte for byte. The simulator app, widget and share extension each contain all 131 adopted files and the manifest.

The updater passed 14 Python GIS tests and 16 Ruby tests (370 assertions), including failures for an unpinned source, mismatched tracking bytes, and a gap at a repaired shared edge. Xcode recorded 1,726 passes and two opt-in fixture skips across RegionKitTests, WhereCoreTests and WhereUITests on iPhone 17 Pro / iOS 27.2. The developer map snapshot suite passed with recording disabled. Architecture, Python/web lint, Swift formatting and repository guidance checks passed.

## Resume point

Plan 07 is complete on [PR #563](https://github.com/kyleve/Stuff/pull/563). [STU-348](https://linear.app/kve/issue/STU-348) remains in review.
