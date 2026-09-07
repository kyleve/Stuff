# Daylight

Daylight turns a dedicated iPhone into a camera for sunrise and sunset photography. It saves original RAW and JPEG resources in Apple Photos and posts selected highlights to Mastodon.

## Setup

1. Run `./ide --no-open` from the repository root.
2. Install with `./Daylight/install --device <identifier>`.
3. Mount the phone in landscape with the rear camera facing the view.
4. Open Daylight and allow Camera access.
5. Select the lens, zoom, and camera exposure compensation.
6. Take a test photo and allow Photos access.
7. Check that one original image appears in Photos.
8. Check **Location and schedule**, then save the settings.
9. Connect power and tap **Start unattended capture**.

The camera preserves Apple ProRAW or Bayer RAW when the selected camera supports it. ProRAW is preferred; Bayer RAW requires 1× zoom. Other configurations save JPEG only. History identifies JPEG-only captures.

The camera uses a fixed landscape orientation. Auto focus, exposure, and white balance settle before each shot. The preview updates at four frames per second.

The default schedule captures 13 photos per event, at five-minute intervals. Each window starts 30 minutes before sunrise or sunset and ends 30 minutes after it. Settings are independent for each event. A sequence keeps its settings after its first slot. Later changes apply to future sequences.

Solar times use the offline NOAA fractional-year equations and the configured time zone. This approximation does not account for terrain, elevation, weather, or window direction. The camera can capture sunset light even when the sun is outside its view.

## Mastodon

1. On your Mastodon server, create a personal application access token.
2. Grant `read:accounts`, `write:media`, and `write:statuses` permissions.
3. Enter the HTTPS server URL and token in **Mastodon**.
4. Tap **Connect account**.
5. Check the connected account and post visibility.
6. Set a caption with `{event}` and `{date}` placeholders.
7. Enable automatic publishing and save the settings.

Each sequence posts one original image after its capture window closes. Vision scores images locally and excludes utility images. Equal scores favor the image closest to the solar event. A failed selection preserves the sequence without a post. Manual test photos never post.

Mastodon receives a resized JPEG without the original metadata. The access token remains in Keychain. Connecting an account leaves automatic publishing disabled until you enable it.

## Unattended operation and recovery

Daylight must stay open and unlocked. The display dims and automatic locking stops while capture is armed. Stopping capture restores the prior display settings.

Reopen Daylight after a reboot or termination. The saved arming setting restores the previous intent. iOS can interrupt the camera in the background. Missed slots remain missed. A slot has a 30-second scheduling tolerance and never triggers a catch-up burst.

Camera permission, Photos permission, thermal pressure, and free storage can pause capture. Staged image files remain available after a failure. Daylight never deletes Photos assets.

Uploads retry while the app is active. The queue preserves media identifiers and submission checkpoints. An uncertain post near the end of Mastodon's one-hour duplicate-protection window requires review. Daylight does not blindly repost it.

Each capture saves as one Photos asset, with RAW as the main resource and JPEG as its companion when available. Interrupted saves use a durable asset receipt for reconciliation. Ambiguous saves remain visible in history and retain their staged files.

## Architecture and extension points

`Daylight` creates shared services once. `DaylightUI` renders observable state. `DaylightCore` owns scheduling, capture, processing, Photos integration, and the archive. `DaylightMastodon` owns the first publishing adapter.

`PublishingDestination` declares the typed events it consumes. Captured-image events support future gallery uploads. Sequence-highlight events support social posts. Each input exposes the original RAW file when available and its JPEG companion. Adapters persist opaque checkpoints through the supplied callback and return a receipt. The coordinator does not switch over adapter names.

Metadata uses atomic, versioned Codable files under Application Support/Daylight. Persisted enum case names are part of the file format. Renaming a case requires an explicit compatibility design. Unknown versions and damaged records surface errors.

## Validation

Run `./test DaylightCoreTests DaylightMastodonTests DaylightUITests` for focused unit coverage. Run `./test --snapshots --only DaylightUISnapshotTests` for image coverage.

[Device acceptance](Daylight/Tests/README.md) covers the checks that need a physical camera. The complete sunrise/sunset cycle needs the eventual mounted phone and a configured Mastodon account.

The website and Instagram adapter are tracked in [TODOs.md](TODOs.md).

## Sources and attribution

RAW capture follows [Apple’s RAW and ProRAW guide](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats).
The solar implementation follows [NOAA solar equations](https://www.gml.noaa.gov/grad/solcalc/solareqns.PDF).
Selection uses Apple's [Vision aesthetics request](https://developer.apple.com/documentation/vision/calculateimageaestheticsscoresrequest).
Publishing follows [Mastodon's status and idempotency contract](https://docs.joinmastodon.org/methods/statuses/).

The app ships its generated license report in `Daylight/Resources/attribution.json`.
Run `./attribution Daylight/Daylight/attribution-sources.json` from the repository root to refresh it.
