# Swift feature delivery

Developers write the app in Swift. In development and beta, they should be able to change **any Swift-authored part of the app** on an installed device. That includes root navigation, entirely new screens, shared logic and calls into platform frameworks. For the App Store, the release owner can keep performance-sensitive code native and compile the rest for dynamic execution. How the code runs and how an update reaches the device are separate release choices.

## Planning checkpoint

Initial proposal, 2026-11-20, against `b9757eccf`. The request covers Swift authoring, live development and beta updates, and per-feature App Store builds. The owner clarified that the whole Swift-authored app should be updatable. The BridgeJS device experiment is ready for a separate execution request. [Linear STU-336](https://linear.app/kve/issue/STU-336/explore-over-the-air-delivery-for-swift-authored-app-features)

## Requirements and planning horizon

| Story | Requirement | Deliverable |
| --- | --- | --- |
| US-01 · Developer edits a feature once | R-01 · Use the same Swift source for native and dynamic builds. R-02 · Live-deploy changes anywhere in the Swift-authored app, including entirely new screens, features and shared logic. | [01 · First device proof](01-device-experiment.md), then [02 · Whole-app coverage](02-release-delivery.md) |
| US-02 · Tester tries the latest flow | R-03 · Offer the same whole-app update workflow to beta testers on an eligible channel. A tester can still open the flow after an interrupted update or offline launch. | [02 · Beta and App Store delivery](02-release-delivery.md) |
| US-03 · Release owner chooses per feature | R-04 · Ship native and dynamic features in one build. Identify which changes can arrive remotely and which require a new app version. | [02 · Beta and App Store delivery](02-release-delivery.md) |

Start with one synthetic flow as a small piece of evidence toward R-02. Where's real onboarding also owns restore, consent, and launch recovery. X-01 keeps production migration outside the experiment. X-02 excludes a standalone Swift-to-JavaScript compiler from the first experiment. Swift-to-Wasm with JavaScript bindings already gives us one route to test. [WhereUI](../../Where/WhereUI/README.md) · [Swift SDK for Wasm](https://www.swift.org/documentation/articles/wasm-getting-started.html)

## What Apple says

Checked 2026-11-20. At WWDC26, Apple described how Goodnotes compiled its existing Swift code to Wasm. Goodnotes measured 35–40× faster bridging between Swift and JavaScript with type-safe bindings compared with dynamic bridging. JavaScriptKit’s experimental BridgeJS plugin generates typed bindings for this boundary. The device experiment will time a real feature call and the full native interaction separately. [WWDC26, Goodnotes benchmark](https://developer.apple.com/videos/play/wwdc2026/262/?time=1057) · [BridgeJS documentation](https://github.com/swiftwasm/JavaScriptKit#bridgejs-plugin)

Safari 27 shipped JavaScript Promise Integration. Apple’s November 16 Safari 27.3 beta notes list Memory64 and relaxed SIMD. Use shipping iOS for the experiment. The sample needs neither beta feature. [Safari 27](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes) · [Safari 27.3 beta](https://developer.apple.com/documentation/safari-release-notes/safari-27_3-release-notes)

| Channel | What the evidence supports | Proposed delivery |
| --- | --- | --- |
| Local development | Apple DTS suggested exploring off-device Wasm compilation for developer-authored plug-ins and referred distribution eligibility to App Review. [DTS discussion](https://developer.apple.com/forums/thread/790932) | Test live reload on an owned, development-signed iPhone. |
| Beta | Guideline 2.2 says TestFlight apps should follow the review rules and significant changes should go through TestFlight App Review. Ad hoc distribution also carries program terms. [Guidelines](https://developer.apple.com/app-store/review/guidelines/#beta-testing) · [License agreement §3.3](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) | Identify the tester audience and proposed change before enabling OTA. Use a new beta build for feature changes while eligibility is unresolved. |
| App Store | Guideline 2.5.2 restricts downloaded code that adds or changes functionality. 4.7 covers specified hosted software and 4.7.2 requires prior Apple permission to expose native APIs to it. The license agreement limits downloaded interpreted code by app purpose, security and storefront use. Delivering additional features outside the named channels generally needs prior written approval. [Guidelines §§2.5.2, 4.7, updated October 16](https://developer.apple.com/app-store/review/guidelines/) · [License agreement §3.3.1 B–C](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) | Bundle the native and Wasm features for review. The cited rules establish no general exception for remote changes to first-party features such as onboarding. Keep that option open only for a specifically supported use case. |

## Decisions and open questions

| ID | Status and impact | Next decision |
| --- | --- | --- |
| Q-01 | Closed 2026-11-20. The owner corrected an earlier selection of flow logic and layout. All Swift-authored code should be updatable. | R-02/R-03 and plan 02 now cover the whole app. [Plan 01](01-device-experiment.md#experiment) samples a new screen, navigation, layout and shared logic. |
| Q-02 | Deferred until [release refinement](02-release-delivery.md#refinement-trigger), when a device result can inform the choice. Blocks a distributed OTA release. | Choose a beta audience and one concrete update, such as changing the order of welcome screens. Check the channel and update against current terms and seek App Review clarification if eligibility remains unclear. |

## Plan review

Reviewed both plans against the corrected Q-01 scope at `b9757eccf` on 2026-11-20. A successful welcome-flow demo establishes the first device result. Whole-app coverage requires the broader demonstration in plan 02. Plan 01 is ready. Plan 02 remains an outline pending device evidence and Q-02. The proposal uses a bundled module as the release baseline and preserves live beta delivery as an open product requirement. Device behavior and App Review eligibility for a particular submission still need evidence.
