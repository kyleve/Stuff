# macOS runner benchmark

This fork measures the snapshot critical path without changing the canonical
`kyleve/Stuff` repository. The benchmark uses `workflow_dispatch` and never
runs automatically.

Every candidate must provide Xcode 27 beta 4 build `27A5228h` and the iOS 27
simulator. A candidate is renderer-compatible only when all 381 checked-in
references pass without re-recording.

## GitHub Actions

Run `.github/workflows/runner-benchmark.yml` with a runner label and workload.
The `metadata` workload only fingerprints the VM. `smoke` exercises three
representative suites. `full`, `shard-1`, and `shard-2` use the repository's
normal `./test` entry point and upload its result bundles and timing report.

## Provider availability

Cirrus CI shut down on June 1, 2026, and Cirrus Runners no longer accepts new
customers. Both are excluded from the executable benchmark. Depot remains
gated on its macOS 26 image adding Xcode 27 beta 4 and the iOS 27 simulator.

## Results — August 9, 2026

No paid candidate is renderer-compatible today, so the benchmark stopped at
the metadata gate instead of running snapshots against a different toolchain.

| Candidate | Result | Evidence |
| --- | --- | --- |
| GitHub `xcode-27` | Eligible control | Apple M1 (Virtual), 3 cores, 7 GiB RAM, macOS 26.5.2, Xcode 27 beta 4 (`27A5228h`), and the iOS 27 simulator. The [metadata run](https://github.com/kve-stuff/Stuff-CI-Benchmark/actions/runs/31353690039) queued for 7 seconds and completed in 44 seconds. A [38-image smoke run](https://github.com/kve-stuff/Stuff-CI-Benchmark/actions/runs/31353849251) queued for 8 seconds and passed unchanged. |
| GitHub `macos-26-xlarge` | Disqualified | The [probe](https://github.com/kve-stuff/Stuff-CI-Benchmark/actions/runs/31354326545) started after 3 seconds but exposed Xcode 26.6 (`17F113`) on image `macos-26-arm64/20260728.0273`, then failed the exact-build gate. The 22-second job cost $0.10 after discounts. |
| Depot `depot-macos-26` | Disqualified before installation | Depot's [current macOS 26 image](https://depot.dev/blog/now-available-macos-26-github-actions) lists Xcode 26.x only. No Depot app was installed and no trial was started. |
| Cirrus | Unavailable | [Cirrus Labs](https://cirruslabs.org/) says Cirrus CI shut down on June 1, 2026, and Cirrus Runners is not accepting new customers. |

The canonical workflow already runs its two duration-balanced snapshot shards
as separate `xcode-27` matrix jobs, so moving the shards to independent
standard runners is not an unclaimed optimization.

The smoke job took 15m58s end to end. Its snapshot step took 15m07s, split
approximately into 6m40s of test-harness pre-build work, 3m46s building, and
4m35s executing 3 suites / 38 images. About 69% of the snapshot step elapsed
before the selected tests began, so the measured queue (8s) was not the source
of the delay.

### Recommendation

Keep the canonical workflow on `xcode-27`. Re-run only the metadata probes when
GitHub's XLarge or Depot's macOS image advertises Xcode build `27A5228h` (or the
repository deliberately moves its checked-in references to a newer renderer).
There is no evidence supporting a runner migration now. Further CI work should
target the cold `./test` setup/generation/build path on the compatible runner.

### Cost and cleanup

- GitHub Team: $4 for one month, with downgrade to Free scheduled for
  September 9, 2026.
- GitHub Actions: $0.10 billable for the XLarge probe. The Actions budget was
  restored to $0 with stop-usage enabled after the probe.
- Depot and Cirrus: $0; no account, app installation, or trial was created.

## Guardrails

- The GitHub organization and repository are disposable benchmark surfaces.
- Workflows receive read-only repository permissions and no secrets.
- The paid-trial ceiling is $75 total.
- The canonical repository, branch protection, and snapshot references stay
  unchanged until a measured winner is selected.
