# Maple Crossing

A full-screen Flutter map using MapLibre and OpenFreeMap’s dark vector style.
The camera starts in downtown Toronto at a 55° pitch. The gradient overlay
stays fixed over the map, and clicking places a pin. No API key is required.

```sh
flutter pub get
flutter run -d chrome
```

Drag to pan, scroll to zoom, and right-drag to adjust pitch and bearing.
The `MapScreen` constructor accepts `initialCenter`, `initialZoom`, and
`initialPitch` (0–60 degrees).

The web entry point loads MapLibre GL JS and CSS. Map styles, fonts, and tiles
require internet access. Map credits remain visible in the corner.

```sh
flutter analyze
flutter test
flutter build web
```

Serve `build/web/` with a static web server for deployment.
The current migration is validated for web; mobile builds have not been tested.

## Highlight a different road

Pass real road geometry to the map (coordinates are longitude, latitude):

```dart
MapScreen(
  road: LineString(coordinates: roadCoordinates),
)
```

The default is the bundled Lauzon Road segment. Replacing `road` updates the
highlight and camera target. `initialCenter` optionally overrides that target.
`RoadHighlightService` in `lib/services/road_highlight_service.dart` owns the
animation and produces the three themed MapLibre layers. In another map, create
it with a `TickerProvider` and road, listen with `AnimatedBuilder`, and pass
`service.layers` to `MapLibreMap.layers`. Call `setRoad` to replace the geometry
and `dispose` when the owner is removed. Geometry must contain at least two valid
coordinates. The service renders supplied geometry; it does not geocode road names.

## Border crossing placeholders

The map displays only Windsor–Detroit road crossings: Ambassador Bridge,
Windsor Tunnel, and Gordie Howe International Bridge. The service filters
both circles and popups to these three crossing IDs.

`assets/data/us_canada_border_crossings.json` is a bundled WGS84 snapshot with
213 coordinate-bearing records from Wikipedia's Canada–United States border
crossing list. Each record has a name, type, region, latitude, longitude, status
classification, and source link. Source attribution/license and coverage limits
are included in the JSON. Data is loaded locally once, with no runtime API calls.

Circles now use the `entrances` array of mapped road inspection checkpoints on
both sides, rather than the original boundary coordinate. Nearby inspection
lanes are grouped and represented by a real checkpoint node. Circle size,
colors, and alignment with the map are unchanged. Cyan/gray remains the source
record's unverified status classification, not live operating status.

Entrance data comes from OpenStreetMap (`barrier=border_control` nodes near listed road
crossings). The JSON includes node links, attribution, data timestamp and matching
method. The bundled snapshot contains 238 markers at 120 crossings. Road-link
verification was unavailable during import; tagged indoor and motor-vehicle-
prohibited checkpoints were excluded, but road access has not been verified. Proximity matching is not manually verified; coverage on either side
may be incomplete. These are inspection checkpoints, not the approach-road
turnoffs. Unmapped, rail and closed crossings are omitted from the entrance
layer; their original reference records are retained.

To regenerate the original crossing inventory (requires `beautifulsoup4`), then
enrich it with Overpass JSON files:

```sh
python scripts/import_border_crossings.py source.html assets/data/us_canada_border_crossings.json
python3 scripts/import_border_entrances.py assets/data/us_canada_border_crossings.json checkpoints.json [checkpoint_roads.json]
```

Overpass query for `checkpoints.json`:

```text
[out:json][timeout:150];
(node["barrier"="border_control"](41,-126,50,-66);
 node["barrier"="border_control"](54,-142,70,-129););
out;
```

The optional `checkpoint_roads.json` validates road membership. To fetch it, replace `out;` with
`way(bn)["highway"];out body;`. The importer groups adjacent lanes within 60 m
and matches checkpoints to the nearest road crossing within 5 km (35 km for
northern stations above 59° latitude). Rebuilding the inventory alone removes
the entrance enrichment, so always run both importers before bundling.

Crossing inventory: Wikipedia contributors, CC BY-SA 4.0,
https://en.wikipedia.org/wiki/List_of_Canada%E2%80%93United_States_border_crossings

Entrance coordinates: © OpenStreetMap contributors, ODbL 1.0,
https://www.openstreetmap.org/copyright

### Local geographic source data

The extracted BBBike OpenStreetMap GeoPackage remains in `assets/planet/` for
future use. It is not bundled or rendered by the app. The map uses its original
OpenFreeMap dark style.

### Visible-area queries

`ViewportGeohashService.cover(bounds)` returns a set of geohashes covering the
view's bounding rectangle. It handles wrapped longitudes/date-line crossings
and automatically reduces precision to cap queries at 256 cells. A pitched or
rotated screen's rectangular cover can include some offscreen area.

Use `MapScreen(onViewportChanged: (area) { /* query area.hashes */ })` to receive
updates after camera movement settles for 150 ms, or subscribe to your own
`ViewportGeohashService` and call `update(bounds)`. The callback also exposes
`area.bounds` and `area.precision`. Geohashes are for geographic data queries;
the renderer's XYZ tile selection uses the same camera bounds directly.

### Web launch screen

The web page shows a black background and `assets/images/maple_crossing_logo_wide.png`
before Flutter starts. Once the initial camera position is applied and MapLibre
reports its first idle frame, the launch screen fades out over 600 ms. Road
pulsing starts after readiness so continuous animation cannot hold the splash
open. Reduced-motion preferences disable the fade. Reload the browser after
changing the HTML launch screen; Flutter hot reload only updates Dart code.

### Border popups and passenger waits

Nearby checkpoints for the same crossing and known direction are combined
within 350 m, retaining an actual checkpoint location. Unknown directions use
a conservative 60 m radius. The circle and popup share the combined location;
the original JSON records are retained.

Upright popup cards follow checkpoint markers and show the crossing name,
travel direction, passenger wait and the provider's update text. Overlapping
cards are culled; zoom in to reveal nearby checkpoints. Cards do not intercept
map gestures. Unknown checkpoint directions show `US ↔ Canada`.

`BorderWaitService` follows `BORDER_WAIT_TIMES_HANDOFF.md` and fetches
`https://transitbarometer.com/api/border.json` at startup and every 60 seconds.
Exact mappings currently cover Ambassador Bridge, Windsor Tunnel and Gordie
Howe International Bridge. Both directions come from the same response. Waits
are the agencies' published passenger-car delays, not measured travel times.
Missing values show `—`; closed/unknown/zero waits show `Closed`, `N/A`, and
`No delay`. Unmapped crossings have no live wait. Refresh failures retain the
last successful response and label it as last known; feed timestamps older
than 15 minutes also receive that label. Timers and requests are disposed
with the map. The map does not wait for the feed to finish loading.
