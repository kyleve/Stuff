#!/bin/bash
set -euo pipefail

if git diff --quiet origin/main...HEAD -- Project.swift \
    ':(glob)**/SnapshotTests/**/*.swift' .circleci/validate_snapshot_inventory.sh; then
    echo "Snapshot definitions and inventory check are unchanged. Skipping Xcode enumeration."
    exit 0
fi

./test --snapshots --shared --os 27.2 \
    --test-artifacts "$CIRCLE_WORKING_DIRECTORY/ci-test-build" \
    --enumerate-suites "$TEST_WORKDIR/suites.txt" \
    --skip-architecture
./snapshot-shards compare-enumeration --enumeration "$TEST_WORKDIR/suites.txt"
