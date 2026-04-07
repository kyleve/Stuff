# Where

There **Where** app is an app designed to track how much time to spend in a given location, usually state by state within the US.

Any time per day spent in a state counts entirely towards a day in that state. So it's possible to be in two states on a given day.



## Build Information

Repo-wide build, formatting, and agent-sync rules live in the root [`AGENTS.md`](../AGENTS.md).

## Layout

| Piece | Role | Path |
|-------|------|------|
| **Where** | iOS app (`com.stuff.where`) | [`Where/`](Where/) — [`Sources/`](Where/Sources/), [`Tests/`](Where/Tests/), [`Resources/`](Where/Resources/) |
| **WhereCore** | SPM library (domain / non-UI) | [`WhereCore/Sources/`](WhereCore/Sources/), [`Tests/`](WhereCore/Tests/) |
| **WhereUI** | SPM library (SwiftUI); depends on **WhereCore** | [`WhereUI/Sources/`](WhereUI/Sources/), [`Tests/`](WhereUI/Tests/) |
| **WhereTesting** | SPM test helpers for Where targets | [`WhereTesting/Sources/`](WhereTesting/Sources/) |

The app target depends on the **WhereUI** package product only; **WhereUI** pulls in **WhereCore** via SPM.

## Xcode / Tuist

Targets are declared in the root [`Project.swift`](../Project.swift) and [`Package.swift`](../Package.swift):

- **WhereTests** — tests the app; depends on the **Where** target and **WhereTesting** (no **StuffTestHost**).
- **WhereCoreTests** and **WhereUITests** — hosted unit tests (see `unitTests` in `Project.swift`): **StuffTestHost** + **WhereTesting** + the corresponding package product.

Regenerate the Xcode project from the repo root with `./ide`.

## Conventions

Match the rest of the repo: **Swift Testing** only, bundle IDs under `com.stuff.*`, and shared cross-feature code in [`Shared/`](../Shared/) (**StuffCore**, etc.) rather than duplicating it under `Where/`.
