# Natural Earth source data

These files are the 1:50m Natural Earth Vector inputs for Throw's offline map.
They come from the `v5.1.2` release.

The generator verifies each file with a pinned SHA-256 value. It removes names
and other attributes that Throw does not use. It keeps geometry, display rank,
and boundary status. It also splits lines at the antimeridian.

| File | SHA-256 |
| --- | --- |
| `ne_50m_coastline.geojson` | `271f1c4c1908312bac6b29d158ea1356544beafc129f260005300913aa5ea283` |
| `ne_50m_lakes.geojson` | `d350b75978b26fe839b797c2c529b2fb8f47fb3983c03f4964e36d5df9378a52` |
| `ne_50m_rivers_lake_centerlines.geojson` | `f286e0ce978fde999ca2d7a78c764be08542e19b63cded52b05c12d5173ccc51` |
| `ne_50m_admin_0_boundary_lines_land.geojson` | `2faac4f6b34386f3d21b6e018cf151f241f00e5c936d44dd17d7d9bfb147fa48` |
| `ne_50m_admin_1_states_provinces_lines.geojson` | `72cca93c850d412628a5da4bc5ebfe21ba4d376eb34611bde6b623ee73f0fdcf` |

Run this command from the repository root after you change an input:

```sh
ruby Throw/ThrowCore/Tools/generate-geography.rb
```

The command writes `Sources/Resources/geography-v1.json`. Commit the inputs,
the generator, and the generated file together.

Natural Earth declares its vector data to be in the public domain. Throw uses
the recommended credit, “Made with Natural Earth.” See the [Natural Earth
terms](https://www.naturalearthdata.com/about/terms-of-use/).
