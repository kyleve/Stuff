#!/usr/bin/env bash
set -euo pipefail
cd "${SRCROOT:?Xcode must supply SRCROOT}"
exec python3 Tools/porthole_export.py
