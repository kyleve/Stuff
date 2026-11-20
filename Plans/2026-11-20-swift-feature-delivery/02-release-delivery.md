# 02 · Update the whole app and choose delivery per feature

**Status** · outline. **Depends on** [01 · Device experiment](01-device-experiment.md). Covers US-01 through US-03 and R-01 through R-04 in the [overview](README.md).

**Development and beta target.** Build a small complete app in dynamic mode, including its entry screen, navigation, features, resources and shared Swift packages. Deploy a revision that adds a feature and changes an existing dependency. The installed client should start the new version with the same host binary. Trace every app-owned module to its artifact. In the update, edit an ordinary SwiftUI view and change when Swift calls an already-available platform API. Verify both changes on the original install. Either unsupported case leaves whole-app coverage unresolved. If a new Apple API needs host support or an entitlement changes, identify exactly which change requires a new signed build.

A release owner should be able to build one app with a performance-sensitive feature compiled natively and onboarding compiled to Wasm. In the proposed build configuration each feature has an execution mode and a separate update source. A bundled Wasm feature changes with the reviewed app build. Remote delivery adds a second decision about the channel and the specific change.

```swift
// Illustrative release choices. Each feature still has one Swift source.
feature(.imageProcessing, execution: .native, updates: .appBuild)
feature(.welcome, execution: .wasm, updates: .appBuild)
```

**Beta evidence.** For an eligible tester channel, demonstrate the whole-app revision reaching an already-installed host. Activate only a verified, compatible artifact. A partial download or incompatible host keeps the previous working flow or the bundled version available offline. Record how to withdraw a bad update.

**App Store evidence.** Inspect one archive containing both execution modes and exercise both features offline. Confirm the release build omits the development endpoint and make the bundled flows accessible to App Review. A change to code selected for native execution ships in a new signed build. Before enabling remote delivery for any Store feature, record the exact proposed update and its applicable review basis. Use the [channel table](README.md#what-apple-says) when deciding which changes require a new build.

## Refinement trigger

Start refinement when plan 01 records its device result. Use the result to choose a representative app and its hardest framework dependency. Resolve [Q-02](README.md#decisions-and-open-questions) during refinement by selecting the beta channel and concrete update, then documenting the basis for distributing it. That answer gates the OTA trial. Specify compatibility and rollback for the chosen route. Implementation has not started.
