#!/usr/bin/env bash
#
# Repository bootstrap for Cursor Cloud agents, run after the checkout.
#
# These VMs are Linux, so this deliberately does none of what `./ide` does:
# no Xcode check, no Tuist, no project generation. See the Cursor Cloud section
# of ../AGENTS.md for what is and isn't possible here.
#
# Cursor may re-run this against cached state, so every step is idempotent.
set -euo pipefail

# mise isn't in the base image. Its official installer is self-contained (no
# Homebrew), same as ./ide --bootstrap uses.
if ! command -v mise >/dev/null 2>&1; then
    echo "==> installing mise"
    curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# A fresh clone's .mise.toml is untrusted, and mise refuses to read an untrusted
# config — including the postinstall hook below.
mise trust

# Installs Ruby and SwiftFormat; Tuist is scoped to macOS in .mise.toml, so it's
# skipped rather than failing the install. The postinstall hook then runs
# ./sync-agents --install, which fetches the external agent skills (Ruby from
# this same install is on the hook's PATH).
echo "==> mise install"
mise install

# Match ./ide: route Git at the repo's hooks so a cloud agent's commits get the
# same SwiftFormat pass as a local one. Now that Tuist is OS-scoped, the hook's
# `mise exec --` calls resolve on Linux instead of trying to install Tuist.
git config core.hooksPath .githooks

echo "==> cloud agent setup complete"
