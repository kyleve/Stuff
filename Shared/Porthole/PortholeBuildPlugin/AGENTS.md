# PortholeBuildPlugin

This host build plugin wires whole-module generation. Read [README.md](README.md), the [group contract](../AGENTS.md), and the [repository contract](../../../AGENTS.md).

- Keep this target dependent only on PackagePlugin and PortholeGenerator.
- Declare all generator inputs and outputs to SwiftPM.
- Emit only the compiled Swift output. Keep standalone catalog reports outside plugin outputs; generated Swift already embeds their complete coverage.
- Write generated files only into the plugin work directory.
- Keep adopting-target compiler flags and normal-source guards in the repository build integration.
- Validate changes with a plugin integration build and the generator tests.
