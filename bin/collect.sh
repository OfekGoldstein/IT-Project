#!/usr/bin/env bash
# bin/collect.sh - one collection run. Takes no arguments; cron runs it.
#
# Writes ONE file, raw/YYYY-mm-dd/HHMM.json (UTC), a JSON object with:
#   open_meteo                 Open-Meteo forecast for the three circuits (array, one object per circuit)
#   openf1_session             OpenF1 metadata of the latest session
#   openf1_stored_session_key  key of the session whose data is stored in THIS file, else null
#   openf1_weather / openf1_laps / openf1_stints
#                              OpenF1 data of the latest session. Fetched only if that session ended at
#                              least 45 minutes ago (OpenF1's free historical tier starts 30 minutes after
#                              the end) and no earlier file already stores it, so each session is stored once.
#                              null = not fetched or the request failed; [] = the API returned an empty list.
#
# A file is written to raw/ only when it is complete and valid JSON, and is never overwritten.
# Needs: bash, curl, jq, GNU date.
set -euo pipefail
cd "$(dirname "$0")/.."

day=$(date -u +%Y-%m-%d)
hm=$(date -u +%H%M)
file="raw/$day/$hm.json"
if [ -e "$file" ]; then
  echo "collect.sh: $file already exists, skipping" >&2
  exit 0
fi

mkdir -p "raw/$day" .tmp
tmp=$(mktemp .tmp/collect.XXXXXX)      # same filesystem as raw/, so the final mv is atomic
trap 'rm -f "$tmp"' EXIT

# get URL [jq-test]: prints the response body only if curl succeeds and the body passes the jq test.
get() {
  local body
  body=$(curl -sf --max-time 30 "$1") || return 1
  jq -e "${2:-.}" >/dev/null 2>&1 <<<"$body" || return 1
  printf '%s' "$body"
}

# 1) Open-Meteo: three circuits in one request (Las Vegas, Lusail, Yas Marina). Time zone stays at the default (GMT = UTC).
om_url='https://api.open-meteo.com/v1/forecast?latitude=36.1147,25.4900,24.4672&longitude=-115.1728,51.4542,54.6031&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,wind_direction_10m,surface_pressure&hourly=temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m'
om=$(get "$om_url" 'type == "array" and length == 3') || {
  echo "collect.sh: Open-Meteo request failed, nothing written" >&2
  exit 1
}

# 2) OpenF1: which session is the latest, and is its data historical (free) and not stored yet?
of1=https://api.openf1.org/v1
sess=$(get "$of1/sessions?session_key=latest" 'type == "array"') || sess=null
key=$(jq -r '.[0].session_key // empty' <<<"$sess" 2>/dev/null || true)
end=$(jq -r '.[0].date_end // empty' <<<"$sess" 2>/dev/null || true)

w=null; l=null; s=null; stored=null
if [ -n "$key" ] && [ -n "$end" ] \
   && [ "$(date -u -d "$end" +%s 2>/dev/null || echo 9999999999)" -le $(( $(date -u +%s) - 2700 )) ] \
   && ! grep -rqsF -- "\"openf1_stored_session_key\": $key," raw; then
  w=$(get "$of1/weather?session_key=$key" 'type == "array"') || w=null
  sleep 1
  l=$(get "$of1/laps?session_key=$key" 'type == "array"') || l=null
  sleep 1
  s=$(get "$of1/stints?session_key=$key" 'type == "array"') || s=null
  # All-or-nothing: store the session only if all three downloads worked. Otherwise store none of it
  # (never a partial copy) and the next run tries again.
  if [ "$w" != null ] && [ "$l" != null ] && [ "$s" != null ]; then
    stored=$key
  else
    w=null; l=null; s=null
  fi
fi

# 3) Build the file in .tmp, check it, then move it into raw/ in one step.
cat > "$tmp" <<EOF
{
  "open_meteo": $om,
  "openf1_session": $sess,
  "openf1_stored_session_key": $stored,
  "openf1_weather": $w,
  "openf1_laps": $l,
  "openf1_stints": $s
}
EOF
jq -e . "$tmp" >/dev/null
chmod 644 "$tmp"
mv -n "$tmp" "$file"
