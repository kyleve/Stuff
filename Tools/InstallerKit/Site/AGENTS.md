# Install-site presentation

This Astro project renders the shared installer website. Read [README.md](README.md),
the [installer rules](../AGENTS.md), the [tooling rules](../../AGENTS.md),
and the [repository rules](../../../AGENTS.md).

- Keep components presentational. Python owns catalog validation, trusted artwork,
  installation URLs, manifests, and publication policy in `../installer_site_data.py`.
- Consume the prepared data through `src/data.ts`. Do not fetch the live catalog during rendering.
  Do not duplicate the public catalog validator in TypeScript.
- Validate the private presentation shape with `src/site-data.ts` before rendering. Keep URL and publication policy in Python.
- Preserve the homepage, app, and channel routes. Use the prepared base path for local links and assets.
  Keep installation links tied to the validated HTTPS manifest URL.
- Distinguish preparing, failed, unpublished, and retired channels. Progress links must use Python's validated workflow URL; only active published releases can render install actions.
- Render app names and commit subjects as escaped text. Never pass catalog text to `set:html`.
- Build through `../installer_update_site.py`. Publish its complete output as one Pages artifact.
  Keep generated files isolated so previews and snapshot builds can run concurrently.
- Share fixture catalogs with `../../Tests/Fixtures/installer_update_fixtures.py`.
  Snapshots must consume the production build, including its emitted CSS and artwork.
- Pin dependencies in the root npm workspace and commit its lockfile. Run the type check,
  retained installer tests, and `./test ToolsSnapshotTests --review` after presentation changes.
