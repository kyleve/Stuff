# Holiday artwork

Holiday is a sparse version 2 theme with Flat as its parent. Its definition is
[HolidayTheme.json](Sources/Resources/Themes/HolidayTheme.json).
It uses the existing surface, image, placement, and motion APIs.

The built-in imagegen tool generated these transparent PNG files:

- [Bells](Sources/Resources/Themes/HolidayBells.png): card ornaments that extend into reserved margins.
- [Evergreen bough](Sources/Resources/Themes/HolidayBough.png): restrained artwork along page and surface edges.
- [Winter woodland](Sources/Resources/Themes/HolidayWoodland.png): the illustrated lower-page background.

The files retain their generated alpha channels. Native SwiftUI supplies text,
controls, borders, layout, and geographic information. The theme document owns
color, typography, placement, opacity, and the bells’ slow movement.
Reduce Motion and snapshots use the document’s static pose.
The body font descriptors omit `design` so headings and figures retain their
own serif and rounded designs.
Welcome cards use separate paper colors behind their region-colored actions.
The calendar supplies a cranberry today marker with an ivory number.

## Generation prompts

### Bells

```text
Production illustration asset for Where's Christmas/Holiday iPhone theme. Cohesive hand-painted storybook style: simple rounded forms, confident dark evergreen outlines, flat gouache color with very restrained grain, refined rather than childish. Palette: forest green #23483C, sage #A4B6A0, cranberry #A63E4C, warm ivory #F8F3E7, muted brass gold #CDA75E. Warm and quiet. True transparent background; no background rectangle, no text, no UI, no emoji, no watermark, no detached drop shadow. Clean antialiased silhouette. Leave a small transparent safety margin so nothing is cut off. A wide compact arrangement of two rounded brass holiday bells tied together with a flowing cranberry velvet bow, one small evergreen sprig and three red berries. Bells have deliberately outlined openings and delicate highlights, ribbon tails curl sideways. Designed to sit across the bottom right edge of an app card and extend into the margin. The full arrangement fits an approximate 4:3 silhouette. It must read clearly at 110 pixels wide. Isolated artwork only.
```

### Bough

```text
Production illustration asset for Where's Christmas/Holiday iPhone theme. Cohesive hand-painted storybook style: simple rounded forms, confident dark evergreen outlines, flat gouache color with very restrained grain, refined rather than childish. Palette: forest green #23483C, sage #A4B6A0, cranberry #A63E4C, warm ivory #F8F3E7, muted brass gold #CDA75E. Warm and quiet. True transparent background; no background rectangle, no text, no UI, no emoji, no watermark, no detached drop shadow. Clean antialiased silhouette. Leave a small transparent safety margin so nothing is cut off. An elegant asymmetrical evergreen bough for the right margin of a winter stationery page. A curved branch rises diagonally from lower right to upper left, with softly rounded fir needles, a few ivory snow caps, sparse cranberry berry clusters and two tiny brass star ornaments. Airy branching silhouette, generous transparent gaps between needles, no dense wreath, no circular badge. Approximate 2:3 vertical silhouette, full uncut branch. This is botanical edge artwork, not an icon.
```

### Woodland

```text
Production illustration asset for Where's Christmas/Holiday iPhone theme. Cohesive hand-painted storybook style: simple rounded forms, confident dark evergreen outlines, flat gouache color with very restrained grain, refined rather than childish. Palette: forest green #23483C, sage #A4B6A0, cranberry #A63E4C, warm ivory #F8F3E7, muted brass gold #CDA75E. Warm and quiet. True transparent background; no background rectangle, no text, no UI, no emoji, no watermark, no detached drop shadow. Clean antialiased silhouette. Leave a small transparent safety margin so nothing is cut off. A quiet little winter woodland scene, wide landscape composition: three snow-capped rounded fir trees of varied heights, one tiny ivory cottage with cranberry roof and warm gold windows nestled among them, a low scalloped snowdrift base. One small gold four-point star above the tallest tree. Restrained storybook detail, layered evergreen and sage with ivory snow. Complete self-contained landscape silhouette about 3:2, transparent everywhere outside the trees, cottage and small snowdrift, including transparent sky. Designed as an illustrated lower-page background with all content readable in a 240-pixel-wide rendering.
```
