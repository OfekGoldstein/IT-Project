# Formula 1 Circuit Weather: Forecast vs. Measured (`IT-Project`)

**Authors:** Ofek Goldstein, Noa Fingerman  
**Repository:** https://github.com/OfekGoldstein/IT-Project/tree/main

---

## 1. What is collected and why

This project collects live weather forecasts from the **Open-Meteo Forecast API** and pairs them with post-session trackside measurements and timing data from the **OpenF1 API** across the final three weekends of the 2026 Formula 1 season:

* **Las Vegas Strip Circuit** (19–21 Nov 2026)
* **Lusail International Circuit, Qatar** (27–29 Nov 2026)
* **Yas Marina Circuit, Abu Dhabi** (4–6 Dec 2026)

Open-Meteo's live Forecast API serves only the newest forecast; each new model run replaces the previous one. (Open-Meteo also offers archive endpoints with their own coverage.) We store the exact response the live API gave at every collection time, so the dataset records how the forecast for a given hour changed as that hour approached, from `0` to `144` hours ahead. This allows us to study two research questions:

1. How well do hourly weather forecasts issued days ahead match the conditions measured at the circuit during Formula 1 sessions, and how does forecast error grow with lead time (`0–144` hours)?
2. How do measured track temperature and wind relate to lap pace and tyre age at the circuit level?

**Scope limitation:** All three circuits are in desert climates, not in temperate European or humid tropical regions, so conclusions apply to dry desert conditions. Measured so far: the five Las Vegas sessions had air temperatures of `11.6–15.3 °C` (OpenF1), and four of the five were dry. Practice 1 was wet: the rain flag is set in `36` of `84` weather records and only `20` laps were driven. Lusail and Yas Marina have not been measured yet; Open-Meteo's estimates for them between 19 and 24 Nov range from `18.6` to `32.8 °C`.

---

## 2. Schema

All timestamps across file paths, raw JSON payloads, and normalized tables are in **UTC**. Full column definitions, units, and source mappings are documented in [`SOURCE.md`](SOURCE.md).

### Raw layer (`raw/YYYY-mm-dd/HHMM.json`)

Each run of `bin/collect.sh` writes one JSON file with six top-level keys:

* `open_meteo`: a JSON array of three objects, one per circuit, in request order (Las Vegas, Lusail, Yas Marina; circuit names are not stored in the file). Each object holds a 7-day hourly forecast (`168` hourly values starting at `00:00` UTC of the collection day) for `temperature_2m`, `precipitation_probability`, `precipitation`, `wind_speed_10m` and `wind_direction_10m`, plus a `current` block (the model's estimate for the moment of the call).
* `openf1_session`: metadata from `/v1/sessions?session_key=latest`, or `null` if the request returned no usable data.
* `openf1_stored_session_key`: the `session_key` whose data is stored in this file, otherwise `null`.
* `openf1_weather`, `openf1_laps`, `openf1_stints`: trackside weather, driver lap durations, and tyre stint records of that session, or `null` when no session is stored in this file.

The first four files (16–19 Nov 2026) are manual samples. The first three store a single Las Vegas Open-Meteo object at the root of the file; the fourth (19 Nov, 07:26 UTC) was produced by a manual run of `collect.sh` and already uses the format above, as do all later files. `normalise.sh` handles both.

### Normalized layer (`data/dataset.csv`)

`bin/normalise.sh` (scheduled for Week 6) aggregates all files in `raw/` into a single idempotent CSV table at `(circuit_name, valid_time_utc)` grain across lead times `0, 24, 48, 72, 96, 120, 144` hours, left-joined with hourly aggregated OpenF1 track weather, median lap duration, dominant tyre compound, and average tyre age (`NA` outside official F1 session hours). The full column list (names, content, units) and the source-to-column mapping are in [`SOURCE.md`](SOURCE.md), sections iii and v.

---

## 3. How to run the project

All scripts under `bin/` are executed from the repository root with no command-line arguments and exit with status `0` on success.

### Repository layout

```text
IT-Project/
├── README.md                  this file
├── SOURCE.md                  data sources, limits and the full schema of data/dataset.csv
├── PAIR.md                    who did what, week by week
├── bin/
│   └── collect.sh             one collection run (normalise.sh, analyse.sh, build.sh, run.sh follow in later weeks)
├── raw/YYYY-mm-dd/HHMM.json   append-only raw files, one per run
├── data/                      dataset.csv and findings.json (planned)
└── site/                      index.html (planned)
```

The full `data/dataset.csv` schema is documented in [`SOURCE.md`](SOURCE.md).

### Active pipeline stages

* **Data collection (`bin/collect.sh`):** Bash with `curl`, `jq` and GNU `date`. On every run it queries Open-Meteo for the three circuits and asks OpenF1 which session is the latest. Only if that session ended at least 45 minutes ago (OpenF1's free historical tier starts 30 minutes after the end) and no earlier file already stores it, it also downloads `/v1/weather`, `/v1/laps` and `/v1/stints`; otherwise those keys are `null`. The file is built in `.tmp/` and moved into `raw/` only when it is complete and valid JSON, and an existing file is never overwritten.
  * **Schedule:** the course server runs it from `cron`: every 5 minutes (`*/5 * * * *`) during all three race weekends and hourly (`0 * * * *`) otherwise. For Las Vegas, 5-minute collection ran from 19 Nov 19:20 UTC to about 22 Nov 22:00 UTC; the same schedule applies to Qatar (27–29 Nov) and Abu Dhabi (4–6 Dec). File names and timestamps are always UTC (`date -u`). The minute offsets may change if the jobs are moved off minute 0 (see section 5).
  * **Manual execution (careful):**
    ```bash
    ./bin/collect.sh
    ```
    Every run writes a new, permanent file into `raw/` (append-only), so test in a scratch clone of the repository, not in the real one.
  * **Getting the data into the repository:** raw files are copied from the course server and committed unchanged.

### Planned pipeline stages (Weeks 6–12)

* `bin/normalise.sh` → `data/dataset.csv` (Week 6)
* `bin/analyse.sh` → `data/findings.json` (Week 8)
* `bin/build.sh` → `site/index.html` and `bin/run.sh` (Weeks 8–9)
* `Dockerfile` and `.github/workflows` CI/CD deployment to GitHub Pages (Weeks 10–12)

---

## 4. Findings

### Operational findings (Las Vegas weekend, 19–22 Nov 2026)

Every number below can be reproduced with the commands at the end of this section.

* **Storage:** `raw/` holds `878` files and `21.93 MB` for 19–22 Nov; the whole folder has `917` files and `22.77 MB` (through 24 Nov 21:00 UTC). A 5-minute day takes about `6.4–6.9 MB` and an hourly day about `0.5 MB`, which agrees with the ~115 MB projection for the whole semester in `SOURCE.md` and stays well below the 500 MB course limit. Each OpenF1 session is stored once, in one larger file (`0.05–0.53 MB` per Las Vegas session).
* **How fast Open-Meteo forecasts change:** the `current` block updates every 15 minutes (`900 s`). The hourly forecast arrays change much more often than hourly for Las Vegas and less often for the Gulf circuits. Distinct hourly arrays seen on 20–22 Nov at different sampling intervals:

  | Circuit | every 5 min | every 15 min | every 30 min | every 60 min |
  | :--- | ---: | ---: | ---: | ---: |
  | Las Vegas | 205 | 159 (78%) | 103 (50%) | 52 (25%) |
  | Lusail | 56 | 42 (75%) | 36 (64%) | 26 (46%) |
  | Yas Marina | 32 | 29 (91%) | 24 (75%) | 22 (69%) |

  For Las Vegas, 5-minute sampling caught four times as many distinct forecasts as hourly sampling; for the Gulf circuits, 15 minutes already captures most changes. We keep the 5-minute schedule for Qatar and Abu Dhabi because storage is not a constraint (about 6.7 MB per day) and it keeps the three weekends comparable.
* **OpenF1 live windows:** OpenF1 treats a session as live from 30 minutes before it starts until 30 minutes after it ends. In all `132` runs inside the five Las Vegas live windows, the `/v1/sessions` request returned no usable data for our unauthenticated client (`openf1_session` is `null`); it succeeded in every run outside them. Each of the five sessions was stored exactly once, 45 minutes after it ended (Practice 1 at 02:15 and Practice 2 at 05:45 on 20 Nov; Practice 3 at 02:15 and Qualifying at 05:45 on 21 Nov; Race at 06:45 on 22 Nov, UTC).
* **Weather at the circuit:** Practice 1 was wet: OpenF1's rain flag is set in `36` of `84` weather records and only `20` laps were recorded (other sessions: `395–989`). Open-Meteo's `current.precipitation` during FP1 was `0.0 mm` in 21 runs and `0.1 mm` in 3 runs, and its hourly forecasts for the 00:00 and 01:00 UTC hours ranged from `0.0` to `0.7 mm`. Measured air temperature across the five Las Vegas sessions was `11.6–15.3 °C`.
* **Data quality:** OpenF1 `track_temperature` is `0.0` in 3 of 476 weather records of the five Las Vegas sessions (isolated sensor glitches); `normalise.sh` will treat them as missing.

*(Quantitative findings on forecast error vs. lead time and on track temperature/wind vs. lap pace will be added after `bin/normalise.sh` and `bin/analyse.sh` are implemented.)*

### Reproducing these numbers

Run from the repository root.

```bash
# size of raw/ for 19-22 Nov
find raw/2026-11-19 raw/2026-11-2[012] -type f -printf '%s\n' | awk '{s+=$1} END {printf "%d files, %.2f MB\n", NR, s/1e6}'

# missing 5-minute slots between 19 Nov 19:20 and 22 Nov 22:00 UTC, counted by minute of the hour
t=$(date -u -d '2026-11-19 19:20' +%s); end=$(date -u -d '2026-11-22 22:00' +%s)
while [ "$t" -le "$end" ]; do f="raw/$(date -u -d @$t +%Y-%m-%d/%H%M).json"; [ -e "$f" ] || date -u -d @$t +%M; t=$((t+300)); done | sort | uniq -c

# runs inside an OpenF1 live window (sessions request returned no usable data)
grep -l '"openf1_session": null' raw/*/*.json | wc -l

# distinct hourly forecasts at 5/15/30/60-minute sampling (idx: 0 = Las Vegas, 1 = Lusail, 2 = Yas Marina)
idx=0
for f in raw/2026-11-2[012]/*.json; do b=$(basename "$f" .json); echo "$b $(jq -c ".open_meteo[$idx].hourly" "$f" | md5sum | cut -c1-12)"; done > /tmp/hourly.txt
for s in 5 15 30 60; do awk -v s=$s '(substr($1,3,2)+0) % s == 0 {print $2}' /tmp/hourly.txt | sort -u | wc -l | sed "s/^/every $s min: /"; done

# Practice 1: rain flags, laps, air temperature (OpenF1)
jq -c '{records:(.openf1_weather|length), rain_flag:([.openf1_weather[]|select(.rainfall>0)]|length), laps:(.openf1_laps|length), air_min:([.openf1_weather[].air_temperature]|min), air_max:([.openf1_weather[].air_temperature]|max)}' raw/2026-11-20/0215.json
```

---

## 5. What broke and how we handled it

* **Runs missing at the top of the hour (20–24 Nov 2026):**
  * **What we saw and how we diagnosed it:** After the Las Vegas weekend we compared the expected with the existing files in `raw/`. In the 5-minute window (19 Nov 19:20 to 22 Nov 22:00 UTC), `21` of `897` expected runs are missing: `20` of them at minute `:00` (`20` of `75` top-of-hour slots, 27%) and one at `:30` (20 Nov 07:30). The other `822` slots lost only that one run. In the following hourly period (22 Nov 23:00 to 24 Nov 21:00), `10` of `47` runs are missing (23 Nov at 12, 14, 17 and 22 h; 24 Nov at 06, 08, 12, 13, 15 and 18 h), all at `:00` because hourly runs start at minute 0.
  * **Cause:** not confirmed. Runs that start at minute 00 fail far more often than at any other minute. Our hypothesis is contention on the shared course server (or its network address) when many jobs start at the same moment, so the Open-Meteo request fails and `collect.sh` correctly writes nothing. We have not seen the error yet because `curl -sf` hides it.
  * **Handling:** The gaps stay gaps: nothing is filled in, and `normalise.sh` treats the missing runs as missing. Planned fix: move our jobs off minute 0 (for example `7 * * * *` hourly and `2-59/5 * * * *` in the 5-minute window), show curl errors (`-sSf`), and retry the Open-Meteo request (`--retry 3 --retry-delay 10 --retry-all-errors`), then compare failure rates before and after.
  * **Why this fix:** the failures are concentrated in one minute of the hour, so changing the schedule tests the hypothesis at almost no cost, and a retry covers short outages without ever writing a partial file.

* **OpenF1 refuses unauthenticated requests during live windows (every session):**
  * **What we saw and how we diagnosed it:** `openf1_session` is `null` in `132` runs. We checked them against the start and end times of the five stored Las Vegas sessions: all `132` fall between 30 minutes before a session starts and 30 minutes after it ends, and none fall outside.
  * **Cause:** OpenF1's free tier serves only historical data; live data needs a paid sponsor account, which the course does not allow.
  * **Handling:** `collect.sh` stores `null` instead of session data, waits until the session is at least 45 minutes past its end, and then stores the session once (`openf1_stored_session_key` marks it). This is expected behaviour, not a bug, and `normalise.sh` leaves these hours as `NA`.

* **First version of `collect.sh` would have stored the same OpenF1 session on every run (found in code review, 18–19 Nov 2026, before deployment on the course server):**
  * **What we saw and how we diagnosed it:** We expected `session_key=latest` to return an empty list between sessions. It returns the whole last finished session instead. The first run that stored the São Paulo race produced a `744,541`-byte file, against about `22 KB` for a normal run.
  * **Cause:** `latest` always points to the most recent session, so every run downloaded and stored the same data again. At the 5-minute cadence that is about `215 MB` per day, which would have used up the 500 MB quota within days.
  * **Handling:** Fixed in commit `2609f3b` (19 Nov): each finished session is stored once, files are written atomically and never overwritten, and failed downloads store `null`.
  * **Why this fix:** it keeps one copy of each session, never leaves a partial file in `raw/`, and stays far below the storage limit.

* **Schema transition between manual files and automated runs (16–19 Nov 2026):**
  * **What we saw and how we diagnosed it:** The first manual samples (from 16 Nov) store a single-circuit Las Vegas Open-Meteo object at the root of the file, while automated runs store a three-circuit `open_meteo` array next to the OpenF1 keys.
  * **Cause:** we validated the single-circuit request first and expanded to the full three-circuit contract before the server deployment.
  * **Handling:** all early files stay in `raw/` unchanged (no history was rewritten), and `SOURCE.md` documents that `normalise.sh` must parse both formats.

---

## 6. What we would do differently

* **Start collecting earlier:** The first automated 5-minute run was on 19 Nov at 19:20 UTC, about 57 hours before the Las Vegas race (22 Nov, 04:00 UTC). Longer lead times exist only from four manual samples (16–19 Nov), so the 0–144 hour analysis will be thin for Las Vegas. For later weekends, hourly collection should begin at least six days before the first session.
* **Keep scheduled jobs away from minute 0 on a shared server:** and show curl errors plus a retry from the start.
* **Log why a run failed:** write stderr to a log file so every gap in `raw/` has an explanation, without ever filling gaps.
* **Test an API's behaviour and response size before writing the script:** a single request for `session_key=latest` would have shown the duplication problem immediately.

*(Additional end-of-project reflections will be added in Week 13.)*
