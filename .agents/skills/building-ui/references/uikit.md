# UI guidance: uikit

## Keep UIKit bridges focused

- For one full-bleed child view controller, complete containment normally and
  set `child.view.frame = view.bounds` in `viewWillLayoutSubviews`. Do not add
  four edge constraints.
- Observe with target/selector and remove by observer identity. Pair every
  `start`-style observation API with `stop`, and remove before re-adding on a
  restart.
- Hide a necessary UIKit workaround behind one focused adapter so SwiftUI views
  keep typed presentation state and do not repeat controller plumbing.
