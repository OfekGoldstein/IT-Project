#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

dir="raw/$(date -u +%Y-%m-%d)"
file="$dir/$(date -u +%H%M).json"

om=$(curl -sf --max-time 20 "https://api.open-meteo.com/v1/forecast?latitude=36.1147,25.4900,24.4672&longitude=-115.1728,51.4542,54.6031&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,wind_direction_10m,surface_pressure&hourly=temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m&timezone=UTC") || exit 1

w=$(curl -sf --max-time 20 "https://api.openf1.org/v1/weather?session_key=latest" || echo "[]")
sleep 1
l=$(curl -sf --max-time 20 "https://api.openf1.org/v1/laps?session_key=latest" || echo "[]")
sleep 1
s=$(curl -sf --max-time 20 "https://api.openf1.org/v1/stints?session_key=latest" || echo "[]")

mkdir -p "$dir"
cat <<JSON > "$file"
{
  "open_meteo": $om,
  "openf1_weather": $w,
  "openf1_laps": $l,
  "openf1_stints": $s
}
JSON
