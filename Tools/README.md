# Stuff Tools

This directory contains importable implementations and direct tests for the
repository's retained Python and Ruby developer tooling. Public commands stay
at their established paths in the repository root; shell launchers own process
orchestration and bootstrap, while structured parsing and policy live here.

The existing CircleCI artifact, JUnit, and snapshot-shard helpers remain Python
because they are already integrated and directly tested. `tla_check.py`
similarly owns TLA+ manifest validation, isolated translation, TLC argv, and
result reporting without requiring Java in its tests. The Xcode-facing root
commands keep process and simulator orchestration in shell; `xcode_results.py`
shares xcresult traversal, `snapshot_reports.py` shares capture reports, and
the command-specific Python modules retain each command's distinct policy.
Filesystem-heavy Ruby generators are require-safe so their behavior can be
exercised against temporary repositories.

## Testing

```bash
python3 -m unittest discover -s Tools/Tests -p 'test_*.py'
mise exec -- ruby -I Tools/Tests -e 'Dir["Tools/Tests/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

Tests must not require Xcode, Java/TLC, networking, or the developer's real
repository state. Add shared fixtures under `Tools/Tests/Fixtures`; otherwise
create the smallest useful input in the test's temporary directory.

[`ADVERSARIAL_TEST_PLAN.md`](ADVERSARIAL_TEST_PLAN.md) records the public
behavior contracts, portability matrix, destructive-operation boundaries, and
mutation review used to accept changes to these tools.
