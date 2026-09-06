# Throw todos

The durable backlog for the Throw feature group. Item format and placement are
owned by the root [`TODOs.md`](../TODOs.md).

# Open issues

## P0s (Must do)

- test(Throw) [needs-design]: Complete the physical output acceptance matrix
  before beta release — the app declares USB-C/HDMI as its guaranteed path and
  AirPlay plus an explicit on-device fallback (`README.md:31-34`), but automated
  scene tests cannot prove real iPhone/iPad adapters, Apple TV behavior,
  independent versus mirrored output, 16:9/16:10/4:3 resolution changes,
  disconnect/reconnect, mirror-fallback exit and accessibility, idle-timer
  restoration, a Wi-Fi-only iPad's manual-location path, local-network denial,
  or quiet/timed-wake behavior. Exercise ADS-B Exchange with invalid, revoked,
  quota-exhausted, and replaced dedicated credentials; compare usage estimates
  with observed request counts; verify source switching never mixes frames;
  profile dense 240-NM traffic at a stable 30 Hz; and finish with an overnight
  powered soak. Verify that Geography stays subtle and readable at 5, 50, and
  240 NM on each projector aspect ratio. Record the devices, OS builds,
  projectors, provider states, and results in the release checklist. (human
  2026-08-24)
- test(Throw) [needs-design]: Revalidate and physically exercise the iOS 27
  external-scene accessory against the GM SDK — the availability-gated adapter
  constructs, retains, unregisters, and migrates `UISceneAccessory` registration
  between controller scenes (`Throw/Sources/ThrowApp.swift:36-119`), while the
  feature contract explicitly treats final-SDK validation as a release gate
  (`AGENTS.md:28-29`). Confirm API compatibility, controller-window
  closure/recreation, and that the iOS 26 manifest and iOS 27 accessory paths do
  not create duplicate output scenes or polling demand. (human 2026-08-24)
- test(ThrowCore) [needs-design]: Revalidate the externally controlled aircraft
  provider contracts immediately before each beta release — implementation was
  checked on 2026-08-24 against the current ADS-B Exchange Personal/RapidAPI
  price, 10,000-request allowance, host, radius path, header contract, and
  acceptable-use terms, plus the current adsb.lol v2 endpoint. Confirm the live
  listings still match the request builders
  (`ThrowCore/Sources/ADSBExchangeRapidAPISource.swift:6-7,38-51,105-128`,
  `ThrowCore/Sources/AdsBLolSource.swift:65-80`) and localized usage copy
  (`ThrowUI/Sources/Resources/Localizable.xcstrings:1731-1771`), then run the
  disclosed five-NM credential test with a dedicated personal key. (human
  2026-08-24)
- docs(Throw) [needs-design]: Obtain ADS-B Exchange authorization and replace
  the personal-client credential architecture before any public distribution —
  v1 accepts a user-owned personal/non-commercial RapidAPI key in device-only
  Keychain (`README.md:36-42`), which is suitable only for the stated personal
  beta. A public release needs written provider approval, the applicable
  commercial terms, and a provider-approved backend or other architecture that
  does not distribute a shared credential in the client. (human 2026-08-24)

## P1s (Should do)

- feat(Throw) [needs-design]: Implement the planned Transit View — the catalog
  reserves Network and Vehicles layers
  (`ThrowCore/Sources/ProjectionExperience.swift:67-74`), and Views presents
  Transit as unavailable
  (`ThrowUI/Sources/Settings/ProjectionViewsSettingsView.swift:38-42,95-102`).
  Select a live provider, define GTFS or equivalent route geometry, and add
  setup and credentials if required. Give its Map runtime independent polling.
  Keep vehicles brighter than dim network and Geography context. (human
  2026-08-26)

# Completed issues
