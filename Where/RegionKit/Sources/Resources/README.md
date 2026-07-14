# Bundled region data

RegionKit ships a **catalog** of available regions plus one GeoJSON file per
region. `RegionCatalog` reads the manifest; `RegionAttributor` loads only the
per-region files for the regions it's asked to attribute (so we never parse the
whole US at launch).

## `regions.json` — the catalog manifest

An ordered array of entries, one per available region:

```json
{ "id": "us-CA", "name": "California", "localizationKey": "region.california",
  "geometry": { "file": "us-CA.geojson" } }
```

- `id` — a **stable data identifier**, never shown to the user. US states are
  `us-<USPS>` (`us-CA`, `us-NY`, …); countries/blocs use a slug (`canada`,
  `european-union`). The `other` catch-all is not in the manifest — it's a
  well-known sentinel with no geometry.
- `name` — the English display name (the source of `Region.localizedName` when
  there's no `localizationKey`).
- `localizationKey` — optional; when present, `localizedName` resolves it from
  `Localizable.xcstrings`, otherwise it falls back to `name`. Only the handful
  with existing translations carry one today.
- `geometry.file` — the per-region file under `regions/`.
- **Array order is the catalog's canonical order** — US states alphabetically,
  then countries/blocs (blocs last). It fixes attribution first-match priority
  (regions are mutually exclusive at our resolution) and the day-count ranking
  tiebreak.

## `regions/<id>.geojson` — per-region geometry

One FeatureCollection per region, a single feature carrying `properties.region`
(the id) + `properties.name`, with a `Polygon` or `MultiPolygon` geometry
(exterior rings; holes aren't modeled). The US files are the individual state
features split out of the Census source; `canada` / `european-union` are the
hand-simplified outlines.

## Regenerating

`regions/` and `regions.json` are **generated** from the source files under
[`../../Tools/source/`](../../Tools/source) by
[`../../Tools/generate-regions.rb`](../../Tools/generate-regions.rb). Re-run it
from the repo root after changing the source data (never hand-edit the split
files or the manifest):

```sh
ruby Where/RegionKit/Tools/generate-regions.rb
```

The `id` map (Census `NAME` → `us-<USPS>`) lives in that script.

## Source data

The inputs below live in [`../../Tools/source/`](../../Tools/source) — they are
**not bundled** (the app ships only the generated per-region files above); they
exist solely so the generator can re-split them.

### `us-states.geojson`

US state boundaries (50 states + DC + PR), `MultiPolygon` per feature with a
`properties.NAME` matching the state's English name (`"California"`,
`"New York"`, …). The generator splits this into one `regions/us-<USPS>.geojson`
per feature.

- Originally `gz_2010_us_040_00_5m.json` (5m resolution, derived from the
  2010 census). 5m sits between the 500k "detailed" and 20m "very
  simplified" tiers — accurate enough that we don't misclassify points
  along the actual state boundary at typical GPS precision, small enough
  to ship in-bundle.
- Source: [eric.clst.org/tech/usgeojson](https://eric.clst.org/tech/usgeojson/),
  converted from the US Census Bureau's Cartographic Boundary Files.
- License: US Government works are not eligible for copyright protection
  (17 U.S.C. § 105). The Census Bureau requests attribution; see the
  Acknowledgements section of the repo `README.md`.

### `canada.geojson`, `europeanUnion.geojson`

Hand-simplified outlines for the non-US regions we currently model. These
are deliberately coarse — they're accurate enough for the spot-check tests
in `RegionAttributorTests` but should be replaced with higher-fidelity
public-domain sources before any production residency-audit use.
