# Swift feature delivery

A developer edits a welcome flow in Swift and sees the change on an installed iPhone. At release time, the team can keep a performance-sensitive feature native and run the welcome flow as WebAssembly (Wasm). The release owner chooses both **how a feature runs** and **how its next version reaches the device**.

## Planning checkpoint

Initial proposal, 2026-11-20, against `b9757eccf`. The request covers Swift authoring, live development and beta updates, and per-feature App Store builds. Research and the first plan review are complete. Next, settle the UI scope in Q-01 and refine the device experiment. Implementation awaits a separate request. [Linear STU-336](https://linear.app/kve/issue/STU-336/explore-over-the-air-delivery-for-swift-authored-app-features)

## Requirements and planning horizon

| Story | Requirement | Deliverable |
| --- | --- | --- |
| US-01 · Developer edits a feature once | R-01 · Compile the same Swift feature into native code or a dynamic artifact. R-02 · See a revised artifact on a development iPhone without reinstalling the host. | [01 · Device experiment](01-device-experiment.md) |
| US-02 · Tester tries the latest flow | R-03 · Deliver live updates over an eligible beta channel. A tester can still open the flow after an interrupted update or offline launch. | [02 · Beta and App Store delivery](02-release-delivery.md) |
| US-03 · Release owner chooses per feature | R-04 · Ship native and dynamic features in one build. Identify which changes can arrive remotely and which require a new app version. | [02 · Beta and App Store delivery](02-release-delivery.md) |

Start with one synthetic flow. Where's real onboarding also owns restore, consent, and launch recovery. X-01 keeps production migration outside the experiment. X-02 excludes a standalone Swift-to-JavaScript compiler from the first experiment. Swift-to-Wasm with JavaScript bindings already gives us one route to test. [WhereUI](../../Where/WhereUI/README.md) · [Swift SDK for Wasm](https://www.swift.org/documentation/articles/wasm-getting-started.html)

## What Apple says

Checked 2026-11-20. Apple showed existing Swift logic running in a browser through Wasm and JavaScriptKit at WWDC26. Safari 27 shipped JavaScript Promise Integration. The November 16 Safari 27.3 beta adds Memory64 and relaxed SIMD. Use shipping iOS for the experiment. The sample needs neither beta feature. [WWDC26, WebAssembly chapter at 16:44](https://developer.apple.com/videos/play/wwdc2026/262/) · [Safari 27](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes) · [Safari 27.3 beta](https://developer.apple.com/documentation/safari-release-notes/safari-27_3-release-notes)

| Channel | What the evidence supports | Proposed delivery |
| --- | --- | --- |
| Local development | Apple DTS suggested exploring off-device Wasm compilation for developer-authored plug-ins and referred distribution eligibility to App Review. [DTS discussion](https://developer.apple.com/forums/thread/790932) | Test live reload on an owned, development-signed iPhone. |
| Beta | Guideline 2.2 says TestFlight apps should follow the review rules and significant changes should go through TestFlight App Review. Ad hoc distribution also carries program terms. [Guidelines](https://developer.apple.com/app-store/review/guidelines/#beta-testing) · [License agreement §3.3](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) | Identify the tester audience and proposed change before enabling OTA. Use a new beta build for feature changes while eligibility is unresolved. |
| App Store | Guideline 2.5.2 restricts downloaded code that adds or changes functionality. 4.7 covers specified hosted software and 4.7.2 requires prior Apple permission to expose native APIs to it. The license agreement limits downloaded interpreted code by app purpose, security and storefront use. Delivering additional features outside the named channels generally needs prior written approval. [Guidelines §§2.5.2, 4.7, updated October 16](https://developer.apple.com/app-store/review/guidelines/) · [License agreement §3.3.1 B–C](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) | Bundle the native and Wasm features for review. The cited rules establish no general exception for remote rewrites of first-party onboarding. Keep that option open only for a specifically supported use case. |

## Open decisions

| ID | Status and impact | Next decision |
| --- | --- | --- |
| Q-01 | Open since the initial request. R-01/R-02. Blocks finalizing what the device experiment must demonstrate. | Should portable Swift choose among existing native screens, or also describe their layout and controls? |
| Q-02 | Deferred until [release refinement](02-release-delivery.md#refinement-trigger), when a device result can inform the choice. Blocks a distributed OTA release. | Choose a beta audience and one concrete update, such as changing the order of welcome screens. Check the channel and update against current terms and seek App Review clarification if eligibility remains unclear. |

## Plan review

Reviewed both plans at `b9757eccf` on 2026-11-20. The device experiment is a draft pending Q-01. Release delivery remains an outline pending device evidence and Q-02. The proposal uses a bundled module as the release baseline and preserves live beta delivery as an open product requirement. Device behavior and App Review eligibility for a particular submission still need evidence.
