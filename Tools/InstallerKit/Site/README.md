# Installer website

Astro renders the shared app library, app pages, and build details.
Python prepares validated data, trusted artwork, install manifests, and the update catalog.
The Pages workflow deploys all files together. GitHub Releases stores the signed IPAs.

## Local development

From the repository root, install the pinned tools and site dependencies:

```bash
mise install
mise exec -- npm ci --prefix Tools/InstallerKit/Site
```

Start the development server:

```bash
mise exec -- npm run dev --prefix Tools/InstallerKit/Site
```

Open `http://localhost:4321/Stuff/`. Astro refreshes the page after a template or stylesheet change.
The default catalog contains two apps, main builds, and PR builds.
Install links refer to synthetic fixture releases.

Select another fixture or port:

```bash
mise exec -- npm run dev --prefix Tools/InstallerKit/Site -- --fixture retired --port 4322
```

Available fixtures are `full`, `retired`, `empty`, `unavailable-history`, and `missing-details`.
These catalogs also supply the WebKit snapshots.

Build and serve the production output locally:

```bash
mise exec -- npm run preview --prefix Tools/InstallerKit/Site -- --fixture full
```

The preview command builds into a temporary directory and removes it after the server stops.
Each invocation has separate generated files, including Astro and Vite caches. A preview can run alongside tests.
Dependency installation needs network access. Rendering and fixture previews work offline.

## Production build

The existing Python command remains the publication entry point:

```bash
python3 -m Tools.InstallerKit.installer_update_site \
  --catalog /path/to/updates.json \
  --repository kyleve/Stuff \
  --feed-url https://kyleve.github.io/Stuff/updates.json \
  --output /path/to/new-site
```

The output directory must not exist. Its parent directory must exist.
Input validation and the Astro build complete before the command exposes the output directory.
The build includes `updates.json`, exact-build manifests, artwork, CSS, and HTML.
The feed URL supplies the deployment base path. Custom domains can use `/`.

## Structure and contracts

`src/pages/` owns routes. `src/components/` owns reusable presentation.
`src/layouts/SiteLayout.astro` supplies the shared document and stylesheet.
`src/data.ts` describes the private presentation input from Python.
The public update schema remains in the Python publication tools and InstallerKit.

`../installer_site_data.py` validates identities and releases, then prepares assets and manifests.
`../installer_update_site.py` runs Astro with that input and stages the complete deployment.
`../installer_site_preview.py` supplies fixture data to the same templates.
The build uses the Node version in `.mise.toml` and dependencies in `package-lock.json`.
The launcher first finds mise through `PATH`, then checks its data directory, the standalone installer location, and Homebrew locations.
Data directory discovery honors `MISE_DATA_DIR`, then `XDG_DATA_HOME`, with `~/.local/share/mise` as the default.
This also supports Xcode and snapshot commands with a minimal `PATH`.

## Validation

From the repository root:

```bash
mise exec -- npm run check --prefix Tools/InstallerKit/Site
python3 -m unittest discover -s Tools/Tests -p 'test_installer*.py'
./test ToolsSnapshotTests --review
```

The retained tests exercise validation, escaped text, routes, manifests, build failures, and concurrent builds.
The WebKit tests compare production output on iPhone and iPad in light and dark appearances.
Their adapter inlines the emitted CSS and images for offline capture.
