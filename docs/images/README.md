# App screenshots

These PNG images are cropped from the running Maple Crossing Flutter web app in Chrome, captured on September 26, 2026. Browser chrome is excluded. The overview and overlay are resized for the README; the road and checkpoint detail crops preserve the original resolution. No map content was composited or generated.

| File | Portion shown |
| --- | --- |
| `map-overview.png` | Windsor–Detroit overview with border checkpoints and the highlighted road |
| `border-connections.png` | Flat cyan checkpoint circles and paired dashed crossing references |
| `border-popover.png` | Windsor Tunnel flag with direction, passenger wait, update time, and checkpoint connector |
| `road-highlight.png` | The red Lauzon Road highlight at one instant of its pulse |
| `map-overlay.png` | Lower dark gradient and softened placeholder message |

The overview and checkpoint captures were taken before the popover threshold was lowered, so wait-time flags are hidden in those images. The road image is a closer view of the highlighted Lauzon Road segment. Popovers now become visible at zoom 10. The “One Moment Please...” overlay is editable placeholder content, not the launch loading indicator. Screenshots are snapshots of development and may differ from subsequent edits.

## Credits

Map imagery: [OpenFreeMap](https://openfreemap.org/), OpenMapTiles, and [OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Crossing inventory: [Wikipedia contributors](https://en.wikipedia.org/wiki/List_of_Canada%E2%80%93United_States_border_crossings), CC BY-SA 4.0. Checkpoint positions: OpenStreetMap contributors, ODbL 1.0. Wait-time integration: [Transit Barometer](https://transitbarometer.com/border-barometer/).

These credits accompany crops whose original on-map attribution lies outside the captured portion. Existing app logo assets remain under `assets/images/`.

The border popover capture shows the real app at zoom 15 or higher. Its displayed wait and timestamp are historical values from the capture session.
