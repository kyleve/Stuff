# GitHub workflow: installable builds

## Ad hoc installable builds

Use the exact label `installable` when the user requests a downloadable iOS PR build:

```bash
gh pr edit <number> --add-label installable
```

The label keeps the latest successful branch build available after later pushes.
It applies to every enabled app distribution workflow in this repository.
It authorizes signing the PR's code, so do not add it to every PR automatically.
Only same-repository PRs qualify. Conflicts fail the installable build before signing.
Closing the PR or removing the label retires its app channels after Pages deploys.
Historical release assets remain available.

Read [the installer guide](../../../../Tools/InstallerKit/README.md) for app registration and shared hosting.
Read the app's distribution guide for its enable variable and signing setup.
The trusted controller and app registration must already exist on `main`.
After labeling, inspect the app's distribution run and follow its summary link.
Verify the built SHA in the plan or summary. The PR controller itself runs from `main`.
Report the install page as ready only after **App Install Site** succeeds.
The shared homepage lists main builds. PR builds live under `/apps/<app-id>/`.
