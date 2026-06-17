#!/usr/bin/env bash
#
# Generate the Xcode project, build the app's compiler index, extract the
# type/relationship graph, then build and open the Mac Catalyst viewer.
#
# Usage:
#   Tools/CodeGraph/run.sh [extra code-graph-extract flags...]
#
# Examples:
#   Tools/CodeGraph/run.sh                  # full: generate + build + extract + open
#   Tools/CodeGraph/run.sh --skip-build     # reuse an existing index store
#   Tools/CodeGraph/run.sh --scheme Where   # index a single scheme
#
# For a live graph that updates as you build, run the extractor in watch mode
# in its own terminal (it blocks): see the message printed at the end.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Tools/CodeGraph
repo="$(cd "$here/../.." && pwd)"                     # repo root
graph="$here/.codegraph/graph.json"

# --watch makes the extractor block forever, so the viewer would never open.
# Steer the user to run it standalone instead.
for arg in "$@"; do
  if [[ "$arg" == "--watch" ]]; then
    echo "run.sh is one-shot; run watch mode on its own:" >&2
    echo "  $here/.build/release/code-graph-extract --repo \"$repo\" --watch" >&2
    exit 2
  fi
done

echo "==> [1/4] building code-graph-extract"
(cd "$here" && swift build -c release --product code-graph-extract)

echo "==> [2/4] extracting graph (tuist generate + build-for-testing + harvest)"
"$here/.build/release/code-graph-extract" --repo "$repo" --output "$graph" "$@"

echo "==> [3/4] generating + building the viewer"
(cd "$here/Viewer" && mise exec -- tuist generate --no-open)
derived="$here/Viewer/.build/DerivedData"
xcrun xcodebuild build \
  -workspace "$here/Viewer/CodeGraphViewer.xcworkspace" \
  -scheme CodeGraphViewer \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$derived" \
  >/dev/null

app="$derived/Build/Products/Debug-maccatalyst/CodeGraphViewer.app"
echo "==> [4/4] opening $app"
open "$app"

cat <<EOF

Graph written to:
  $graph

Pick that file from the viewer's open panel once. The app keeps a
security-scoped bookmark and hot-reloads whenever graph.json changes, so you
can leave it open and re-run this script — or run a live extract that rewrites
the graph as you build:

  $here/.build/release/code-graph-extract --repo "$repo" --watch
EOF
