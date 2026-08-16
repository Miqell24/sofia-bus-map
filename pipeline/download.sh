#!/usr/bin/env bash
# Downloads input data: Sofia GTFS (BGNAP), OSM networks (Overpass), MapLibre GL.
# Everything is cached — re-running only fetches what is missing.
#
# ONE feed covers the whole CGM network (Център за градска мобилност): buses,
# trolleybuses, trams and the M1–M4 metro, split by route_type at build time.
#
# The feed is published on the Bulgarian National Access Point (sipbg.gov.bg)
# and rebuilt every night, so its download link carries a fresh id each day.
# The id is resolved through the portal API instead of being hard-coded:
#   dataset -> subsets (format=gtfs-static) -> files (is_latest) -> /download
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs data/osm web/vendor

# A downloaded extract is only accepted if it PARSES and carries a plausible
# number of elements. `grep -q '"elements"'` — the guard this family used
# everywhere — passes on a truncated response too: Brașov's roads arrived as a
# 65 kB fragment that still contained the string, was taken for complete, and
# silently skipped the city (16.08.2026).
# The minimum differs by extract: a road network runs to tens of thousands of
# ways, a city rail network to a few hundred, so the caller passes its own floor
# rather than sharing one.
# A rejected file is deleted rather than left behind — the `[ ! -f … ]` gates
# below only ask whether the file exists, so a fragment on disk would be taken
# for a finished download on the next run.
ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

NAP="https://sipbg.gov.bg/bgnap/portal/api/catalog"
DATASET="650438a1-1ae4-4cc4-a70e-614e3e7ec5e2" # "Sofia public transport", CGM

# 1) GTFS — resolve today's file id, then fetch it
if [ ! -f data/gtfs/routes.txt ]; then
  echo "== BGNAP: resolving the latest GTFS file =="
  SUBSET=$(curl -fsS --max-time 60 "$NAP/datasets/$DATASET/subsets?locale=en" \
    | python3 -c 'import sys,json;print(next(s["id"] for s in json.load(sys.stdin) if s["format"]=="gtfs-static"))')
  FILE_ID=$(curl -fsS --max-time 60 "$NAP/subsets/$SUBSET/files?format=gtfs-static" \
    | python3 -c 'import sys,json
fs = json.load(sys.stdin)
if not fs: raise SystemExit("BGNAP lists no GTFS file for this dataset")
f = next((x for x in fs if x.get("is_latest")), fs[0])
print(f["id"], f["filename"], file=sys.stderr)
print(f["id"])')
  curl -fL --retry 3 --max-time 600 -o data/sofia-gtfs.zip "$NAP/files/$FILE_ID/download"
  unzip -o data/sofia-gtfs.zip -d data/gtfs
fi

# 2) OSM — roadways over the whole municipality (GTFS stops extent 42.48–42.85 N,
#    23.08–23.61 E plus margin: Bankya in the west, the Vitosha villages south)
if [ ! -f data/osm/sofia.json ]; then
  echo "== Overpass (roads) =="
  Q='[out:json][timeout:900];way(42.44,23.02,42.90,23.66)["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];out geom;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 900 -o data/osm/sofia.json --data-urlencode "data=$Q" "$EP" \
       && ok_json "data/osm/sofia.json" 2000; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/sofia.json; echo "Overpass: all mirrors failed" >&2; exit 1; }
fi

# 2b) OSM — rails for the tram and metro modes: tram tracks, metro tunnels
#     (railway=subway; M1/M2/M4 share the central tunnel) and light_rail/rail
#     for the shared corridors. Same bbox as the roads.
if [ ! -f data/osm/sofia-rail.json ]; then
  echo "== Overpass (rails) =="
  QT='[out:json][timeout:300];way(42.44,23.02,42.90,23.66)["railway"~"^(subway|tram|light_rail|rail|construction)$"];out geom;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 300 -o data/osm/sofia-rail.json --data-urlencode "data=$QT" "$EP" \
       && ok_json "data/osm/sofia-rail.json" 40; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/sofia-rail.json; echo "Overpass (rails): all mirrors failed" >&2; exit 1; }
fi

# 2c) OSM — every NAMED feature in the same bbox, tags only. Not geometry: this
#     is the case dictionary. The CGM feed shouts its stop names in capitals,
#     while Bulgarian writes sentence-style ("Западен парк", "ж.к. Иван Вазов")
#     — OSM spells the same words properly on streets, parks, districts and
#     churches. Per-key union instead of a key regex: the regex form 504s on
#     every Overpass mirror. See pipeline/lib/bulgarian.mjs.
if [ ! -f data/osm/sofia-names.json ]; then
  echo "== Overpass (names for the Bulgarian dictionary) =="
  B='42.44,23.02,42.90,23.66'
  QN="[out:json][timeout:600];(nwr($B)[name][amenity];nwr($B)[name][place];nwr($B)[name][tourism];nwr($B)[name][leisure];nwr($B)[name][shop];nwr($B)[name][building];nwr($B)[name][railway];nwr($B)[name][public_transport];nwr($B)[name][natural];nwr($B)[name][waterway];nwr($B)[name][landuse];nwr($B)[name][historic];nwr($B)[name][office];nwr($B)[name][man_made];);out tags;"
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 600 -o data/osm/sofia-names.json --data-urlencode "data=$QN" "$EP" \
       && ok_json "data/osm/sofia-names.json" 2000; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/sofia-names.json; echo "Overpass (names): all mirrors failed" >&2; exit 1; }
fi

# 3) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

echo "OK — data ready:"
du -sh data/sofia-gtfs.zip data/osm/sofia.json data/osm/sofia-rail.json 2>/dev/null || true
