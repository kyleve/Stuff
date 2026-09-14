# PortholeUI

This module owns the opt-in developer debugger interface. Read [README.md](README.md), the [group contract](../AGENTS.md), and the [repository contract](../../../AGENTS.md).

- Keep application-specific context capture and resource ownership in the host application.
- Freeze the presentation origin before debugger navigation begins.
- Attach one UIKit presentation anchor per presentation controller. Use its own window's topmost presenter; never search global windows or add competing sheet bindings.
- Notify the UIKit anchor directly when presentation changes. Keep its observer weak and complete owned transitions after detachment.
- Resolve evidence through its recorded scope generation and source hash. Never attach an expired handle to a replacement scope.
- Bind remote evidence readers and invocation closures to their original connection session. Verify reconstructed source content before display.
- Read complete module coverage through shared executor capabilities. Keep planned support distinct from installed status, and never offer calls for inactive declarations.
- Keep coverage pages bounded and reject results after search replacement or cancellation. Source links retain the captured scope and file hash.
- Open object metadata without evaluating getters. Route selected APIs through the shared approval executor.
- Use the shared registry for every native call and trusted UI approval.
- Offer Watch only for callable classified reads. Freeze form arguments and use the shared observation client; keep sampling in the runtime.
- Stop a watch when its invocation view disappears. Reject delayed samples after stop or replacement, and keep an unconfirmed stop retryable.
- Keep credentials in provider credential stores. Never put them into captured context or console values.
- Keep raw window capture in this excluded module. Export only screenshot evidence that rejects live capture while debugger UI is visible.
- Create remote host credentials and listeners only after explicit activation. Disable the host before its scope expires.
- Keep one investigation library and one journal actor per investigation at the presentation composition boundary.
- Keep agent setup failures separate from runtime availability. Show the failure in Ask and preserve saved investigations when retrying.
- Keep one GitHub client and workspace store per presentation controller. Expose scratch edits through the executor; keep publication behind native review.
- Keep CI results bound to the exact saved proposal fingerprint and published commit. Reject delayed results after review changes.
- Compare installed source with the fixed repository base separately from the patch. Keep unresolved publication edits locked until reconciliation.
- Own one scope refresh task per presentation. Coalesce attachment readers; cancel and invalidate the owned task on dismissal or explicit replacement.
- Keep views presentational and asynchronous work in observable MainActor models.
- Seed the public debugger view with its own Broadway root.
- Use developer-facing literal strings in every build configuration.
- Keep recovery descriptions and actions scrollable at accessibility text sizes.
- Share fixture models with snapshot readiness hooks. Wait for actual model state before measurement and capture; temporary rehosting must not restart completed loads.
- Cover model state with Swift Testing and public surfaces with SnapshotKit.
- Keep the UIKit dependency conditions on both iOS and Mac Catalyst in the root package manifest.
