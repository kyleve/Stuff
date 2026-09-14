# PortholeApp

This app composes the Porthole remote client. Read [README.md](README.md) and the
repository [contract](../../../AGENTS.md).

- Keep transport and credentials in PortholeRemote and views in PortholeUI.
- Create one client model per application process and inject it into the root view.
- Do not add an approval endpoint or weaken certificate enrollment.
- Test behavior in the owning library test bundle.
- Preserve the Release Mac Catalyst compilation check in the Porthole compiler CI job.
- Keep this app's generated attribution report in Resources and its declared sources beside this file.
- Keep acknowledgement presentation in the app; keep report decoding in CreditKit.
