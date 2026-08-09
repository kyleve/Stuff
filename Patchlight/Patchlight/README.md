# Patchlight host

The thin iPad/Mac Catalyst executable. `PatchlightApp` installs `AppDelegate`,
which selects one production or DEBUG Inspector runtime before launch and then
renders the root supplied by PatchlightUI.

The host owns no GitHub, persistence, review, or visual policy. Its bundle ID is
`com.stuff.patchlight`; Catalyst uses the App Sandbox with outgoing network
access. Build it through the `Patchlight` or `Patchlight-Catalyst` shared scheme.
