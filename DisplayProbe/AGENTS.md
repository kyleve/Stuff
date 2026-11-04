# DisplayProbe

DisplayProbe is a standalone UIKit diagnostic app. See [README.md](README.md) and the [repository rules](../AGENTS.md).

- Keep this app independent of Where and private device APIs.
- Read the screen through the measured window's `UIWindowScene`. Never use `UIScreen.main` or infer panel topology from dimensions.
- Keep native pixels, screen points, scene points, and window points separate. Preserve UIKit's coordinate order for each value.
- The calibration grid measures its own view. Its midpoint is not a detected physical hinge.
- Use system UIKit appearance. Grid spacing is a measurement interval, not an appearance token.
- This developer-only diagnostic uses English literal labels and public API names. It has no localization catalog or third-party dependencies.
- Saved readings remain in memory until the app closes. Export requires the user's Share action.
- Run `./test DisplayProbeTests`. Validate the grid and live readings on a simulator, then verify physical-device behavior separately.
