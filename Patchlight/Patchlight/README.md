# Patchlight host

The thin iPad/Mac Catalyst executable. `PatchlightApp` installs `AppDelegate`,
which selects one production or DEBUG Inspector runtime before launch and then
renders the root supplied by PatchlightUI.

The regular v1 runtime is foreground-only: it constructs PatchlightUI's
application launcher with a foreground lifecycle reason so the first window
always builds the signed-out or signed-in product surface. Patchlight has no
headless/background entry point in v1.

The host owns no GitHub, persistence, review, or visual policy. Its bundle ID is
`com.stuff.patchlight`; Catalyst uses the App Sandbox with outgoing network
access. Both supported variants declare the app's default Keychain access group;
the Catalyst entitlement combines it with the sandbox/network capabilities and
uses automatic Apple Development signing so the provisioning profile authorizes
that group. Build through the `Patchlight` or `Patchlight-Catalyst` shared scheme.
