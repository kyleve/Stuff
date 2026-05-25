# Bundled region polygons

These GeoJSON files back `RegionAttributor.bundled`. They are loaded once at
process start, indexed, and consulted for every coordinate-to-`Region`
attribution.

## `us-states.geojson`

US state boundaries (50 states + DC + PR), `MultiPolygon` per feature with a
`properties.NAME` matching the state's English name (`"California"`,
`"New York"`, ...). `RegionAttributor` only pulls the names mapped from
`Region` cases; the rest of the features are ignored at load time.

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

## `canada.geojson`, `europeanUnion.geojson`

Hand-simplified outlines for the non-US regions we currently model. These
are deliberately coarse — they're accurate enough for the spot-check tests
in `RegionAttributorTests` but should be replaced with higher-fidelity
public-domain sources before any production residency-audit use.
