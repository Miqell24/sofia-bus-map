# Sofia Public Transport — interactive map

Interactive, poster-grade map of the **Sofia** network run by Център за градска
мобилност (CGM): city and night buses, trolleybuses and battery-electric lines,
the tram network and the M1–M4 metro drawn in the official line colors — 140
lines along the real street and track geometry.

## Live

**https://miqell24.github.io/sofia-bus-map/** — GitHub Pages from `main:/docs`.

Everything comes from ONE feed — the CGM GTFS bundle published on the Bulgarian
National Access Point ([sipbg.gov.bg](https://sipbg.gov.bg/bgnap/portal/en/catalog),
CC BY 4.0) — split by `route_type` at build time:

| mode | route_type | lines | graph |
|---|---|---|---|
| buses | 3 | 100: city lines, night lines N1–N4, express X9–X43 | OSM roadways |
| trolleybuses | 11 | 17: ТБ1–ТБ11 plus the battery-electric lines CGM files under the same type | OSM roadways |
| trams | 0 | 19: ТМ1–ТМ27 | `railway=tram` tracks |
| metro | 1 | 4: M1, M2, M3, M4, colors from `routes.txt` | `railway=subway` tunnels |

Build quirks worth knowing:

- **Every mode is numbered from 1**, so bus 9, trolleybus 9 and tram 9 are three
  different lines. Bare numbers would weld the bus and trolleybus networks
  together (both ride the road graph) and make the line list ambiguous, so the
  non-bus street modes carry the operator's own prefixes — the ones CGM uses in
  its route ids: **ТБ** = тролейбус, **ТМ** = трамвай. Buses keep the bare
  number, the metro keeps M1–M4.
- **A track tagged `railway=construction` counts as the kind it is being built
  as.** OSM lags behind reopenings: tram 6 was carrying service through Надежда
  while its ways still said `construction=tram`, which tore a 440 m hole in the
  line. The road graph has accepted `highway=construction` from the start for
  the same reason — the GTFS shape is the evidence that service runs there.
- **Routes without trips are skipped by construction.** The feed defines ~60
  routes that are not scheduled at all (tram-replacement buses `5TM`…`22TM`, a
  metro-replacement `M3` bus, dormant trolleybus variants); they never reach the
  map because the pipeline builds its line list from `trips.txt`.
- Suffix letters arrive in both alphabets ("22A" latin, "12А" cyrillic). The
  glyphs are identical, so latin lookalikes are folded into cyrillic —
  otherwise one line can appear twice under visually equal names.
- Stop names are printed exactly as the feed writes them (mostly ALL CAPS
  cyrillic), same as in the Athens and Thessaloniki maps.

Match quality: mean error ~1.3 m on the trams, ~7 m on the metro (tunnel shapes
are coarse) and ~4.8 m on the buses, with no broken runs anywhere.

## Pipeline

`npm run download` resolves the current GTFS file through the BGNAP portal API
(the link carries a fresh id every night), then fetches OSM roadways and rails
(Overpass, bbox 42.44–42.90 N / 23.02–23.66 E) and MapLibre GL. `npm run build`
map-matches every line (HMM/Viterbi on the OSM graphs) and writes GeoJSON to
`data/out/`. `npm run serve` hosts the map at http://localhost:8137.

Data: CGM Sofia timetables via BGNAP (CC BY 4.0) · base map © OpenFreeMap /
OpenMapTiles / OpenStreetMap contributors.
