# Patchlight Host – Module Shape

Thin `com.stuff.patchlight` iPad/Catalyst composition host; see
[`README.md`](README.md), product [`AGENTS.md`](../AGENTS.md), and root
[`AGENTS.md`](../../AGENTS.md).

Select one class-bound production or DEBUG Inspector runtime before process
launch and forward lifecycle/root calls through it. Import PatchlightUI and
composition dependencies only; feature behavior belongs below. Do not add
shelling out, arbitrary filesystem access, iPhone destinations, or a second
account-scope factory.
