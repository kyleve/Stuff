# Geography source data

`manifest.json` pins the source archives for Throw's offline map. The manifest
records each official URL, archive SHA-256 value, ZIP member, data release, and
display policy.

The raw archives are not tracked. The default cache is `cache/`, which this
directory ignores. A clean app build uses only the committed
`geography-v2.json` archive and does not use the network.

`aircraft-types-manifest.json` separately pins the Mictronics aircraft type
archive used by `../generate-aircraft-types.rb`. Pass a downloaded archive with
`--archive`. The generator verifies its digest before it reads the ZIP. The
generated resource contains no registrations, operators, aircraft identities,
or live observations.

## Required archives

The default archive uses these inputs:

| Provider | Release and scale | Input | Output kind |
| --- | --- | --- | --- |
| Natural Earth | 5.1.2 collection, 1:10m | Coastline | `coastline` |
| Natural Earth | 5.1.2 collection, 1:10m | Lakes | `lake` |
| Natural Earth | 5.1.2 collection, 1:10m | Rivers and lake centerlines | `river` |
| Natural Earth | 5.1.2 collection, 1:10m | Admin-0 land boundaries | `national-boundary` or `disputed-boundary` |
| Natural Earth | 5.1.2 collection, 1:10m | Admin-1 boundaries outside the United States | `regional-boundary` |
| Census cartographic boundaries | 2025, 1:500k | State polygons | `regional-boundary` |
| Census cartographic boundaries | 2025, 1:500k | County polygons | `county-boundary` |
| Census TIGER/Line | 2025, source resolution | Nationwide Primary Roads | `primary-road` |

The eight downloads use approximately 65 MiB. The generator reads the SHP and
DBF members directly from each ZIP file. It does not require GDAL or a GeoJSON
conversion.

Natural Earth URLs include the `5.1.2` release. Census URLs include the `2025`
vintage. The SHA-256 values protect the build if a server changes a file.

## Generate the archive

Run this command from the repository root:

```sh
ruby Throw/ThrowCore/Tools/generate-geography.rb --fetch
```

The command fetches a missing archive into the ignored cache. It rejects any
archive that does not match the manifest digest. Then it writes
`Throw/ThrowCore/Sources/Resources/geography-v2.json`.

To use an existing cache, run this command:

```sh
ruby Throw/ThrowCore/Tools/generate-geography.rb \
  --source-directory /absolute/path/to/cache
```

Commit the manifest, generator, and generated archive together. The
`expectedOutput` object lets an offline test make sure that the committed file
matches the last pinned generation.

## Selection and level of detail

The generator stores each path once. The runtime uses `detailLevel` to select
paths for the current Map radius:

| Detail level | Largest Map radius |
| --- | ---: |
| `wide` | 240 NM |
| `standard` | 80 NM |
| `local` | 20 NM |
| `neighborhood` | 8 NM |

Natural Earth features use their `min_zoom` and `scalerank` values. Wide data
has `min_zoom` at most 5 and `scalerank` at most 4. Standard data has
`min_zoom` at most 8 and `scalerank` at most 8. Other features are local.

Census state boundaries are wide. County boundaries are standard when either
adjacent county has at least 5,000,000,000 square meters of land. Other county
boundaries are local.

Interstate primary roads (`RTTYP=I`) are wide. Other S1100 primary roads are
standard. The generator does not store road names or identifiers.

The generator simplifies all linework to 0.005 NM. This keeps deviations below
approximately one screen pixel at the smallest Transit Map radius on common
projector resolutions. Densification limits every output segment to 10 NM.

The nationwide Census TIGER coastline supplies the `neighborhood` tier. When
it intersects an 8 NM-or-smaller viewport, it replaces the broader coastline
tiers for that viewport. Other line kinds remain additive across detail tiers.

## Priority and duplicate geometry

The generator processes inputs by numeric priority. Census roads have the
highest priority. Census state and county boundaries have priority over
Natural Earth regional boundaries.

The Natural Earth admin-1 input excludes United States features. Census state
boundaries replace those features. For Census polygons, the generator keeps
only edges shared by two polygons. Thus state and county outlines do not add a
second coastline or national border.

The generator removes identical paths and segments in each semantic group. If
two features have the same priority, the wider detail level has priority. The
semantic kind and geometry provide the remaining deterministic order.

Names and all unused source attributes are absent from the output. The archive
contains source credit, geometry, bounds, semantic kinds, and detail levels.

## Deferred secondary roads

The default manifest does not include state Primary and Secondary Roads files.
A California 2025 sample added 4,750 paths, 35,094 coordinates, and 795,159
encoded bytes after the S1200 filter.

The official Census directory contains 56 state and territory archives. Their
listed compressed sizes total approximately 281 MiB. A size-based projection
adds approximately 110,000 paths nationwide, which exceeds the 100,000-path
archive limit before other layers.

Do not add state files without pinned SHA-256 values. Measure a representative
set first. Then add only the selected archives as normal manifest inputs.

## Terms and credit

Natural Earth declares its vector data to be in the public domain. Throw uses
the requested credit, “Made with Natural Earth.” See the [Natural Earth
terms](https://www.naturalearthdata.com/about/terms-of-use/).

The U.S. Census Bureau produces the cartographic boundary and TIGER/Line
files. See the [2025 cartographic boundary files](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.2025.html),
the [2025 TIGER/Line files](https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.2025.html),
and the [Primary and Secondary Roads archive](https://www2.census.gov/geo/tiger/TIGER2025/PRISECROADS/).
