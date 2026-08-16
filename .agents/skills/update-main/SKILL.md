---
name: update-main
description: Safely updates the primary, non-linked checkout of this repository to the latest origin/main. Use when the user explicitly invokes $update-main or asks to fast-forward their ordinary main checkout; never use for a Codex-managed or other linked worktree.
---

# Update Main

Update only an ordinary checkout's `main` branch through the repository-owned
`./worktree --update-main` command.

1. Resolve and enter the checkout root with `git rev-parse --show-toplevel`.
2. Read the absolute Git directory and common Git directory:

   ```bash
   git rev-parse --absolute-git-dir
   git rev-parse --path-format=absolute --git-common-dir
   ```

   Refuse to continue when they differ. That identifies a linked worktree;
   direct the user to its **Update to latest main** environment action instead.
3. Require `git branch --show-current` to equal `main`. Refuse detached HEADs
   and other branches rather than moving them.
4. Require `git status --porcelain` to be empty. Report the changed paths and
   stop when the checkout has local changes.
5. Record `git rev-parse --short=8 HEAD`, then run `./worktree --update-main`
   from the checkout root. Do not replace it with `git pull`, a merge, or a
   rebase: the script owns fetching, ancestry checks, and the fast-forward-only
   update.
6. Report whether the checkout was already current or the old and new short
   commit IDs. Preserve and surface any refusal from the script.

Never commit, push, stash, discard changes, or switch branches as part of this
skill.
