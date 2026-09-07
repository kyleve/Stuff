# Device acceptance

The root composition is built by Stuff-iOS-Tests. Core, adapter, and UI tests exercise the injected services.

1. Install with `./Daylight/install --device <identifier>`.
2. Allow Camera and Photos access.
3. Take a test photo.
4. Open the image in Photos. On a supported lens, confirm the asset contains RAW and JPEG resources.
5. Check the saved image orientation and full capture resolution.
6. Take another test shot and check that it creates exactly one new Photos asset.
7. On the eventual camera phone, run one complete sunrise and sunset cycle.
8. Check 13 scheduled photos per event, heat behavior, and screen restoration.
9. Disconnect Wi-Fi during a sequence.
10. Restore Wi-Fi and check that exactly one selected image posts.

The final cycle requires the mounted camera phone and a configured Mastodon account. Simulator tests cannot prove these hardware behaviors.
