# SOURCE.md — Formula 1 circuit weather, forecast vs. measured

This file describes our data sources, what we collect, the schema of `data/dataset.csv`, and the limits of the data. All timestamps are UTC.

* **Research question:** How well do hourly weather forecasts issued days ahead match the conditions measured at the circuit during Formula 1 sessions, and how does the error grow with lead time?
* **Circuits and weekends (end of the 2026 season):** Las Vegas Strip Circuit (19–21 Nov), Lusail International Circuit, Qatar (27–29 Nov), Yas Marina Circuit, Abu Dhabi (4–6 Dec).

## i. Data sources

| Name | Address | Data format | Key or username required | License | Sampling frequency |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Open-Meteo Forecast API** (primary source) | `https://api.open-meteo.com/v1/forecast` | JSON | No | Data: CC BY 4.0 (attribution required). Free API: non-commercial use, under 10,000 calls/day | Course server `cron`: every 5 minutes (`*/5 * * * *`) during race weekends (starting with Las Vegas 19–21 Nov to evaluate sub-hourly value) and hourly (`0 * * * *`) outside race windows |
| **OpenF1 API** (second source) | `https://api.openf1.org/v1/weather`, `/v1/laps`, `/v1/stints` | JSON | No (free historical endpoints only; paid live tier is not used) | CC BY-NC-SA 4.0; intended for educational and non-commercial use | Collected alongside `Open-Meteo` on every `collect.sh` run; returns empty arrays (`[]`) until a session moves to historical tier (~30 min after session end) |

* **Attribution:** The final site will show a visible credit link to Open-Meteo next to the weather data and link to `openf1.org` as well.

## ii. What is collected

1. **Weather forecasts (`Open-Meteo`).**
   On each run, `bin/collect.sh` queries Open-Meteo for all three circuit coordinates (`Las_Vegas`: `36.1147, -115.1728`; `Lusail`: `25.4900, 51.4542`; `Yas_Marina`: `24.4672, 54.6031`) using the variables below and default settings (7 forecast days, GMT/UTC time zone):
   * `current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,wind_direction_10m,surface_pressure`
   * `hourly=temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m`

   Each circuit object holds a 7-day hourly forecast: 168 values per variable, starting at `00:00` UTC on the day of collection. It also holds a `current` block (the model's estimate for the moment of the call), which stays in `raw/` and is not used in `dataset.csv`. For a collection in UTC hour `h` (`0–23`), the last forecast value is `167 - h` hours ahead, so lead times from `0` to `144` hours are always available. Because the live Forecast API overwrites prior model runs, collecting continuously records how the forecast for a given hour evolved as that hour approached.

2. **Measured track conditions and session context (`OpenF1`).**
   On the same run, `bin/collect.sh` queries OpenF1's unauthenticated historical endpoints (`/v1/weather`, `/v1/laps`, `/v1/stints`) for measured trackside air temperature, asphalt track temperature, wind speed, rainfall status, driver lap durations, and tire stint records. OpenF1 retains historical sessions from the 2023 season onward; during active or non-race periods where no new historical records are returned, those endpoint payloads are stored as `[]`.

3. **Raw file storage (`raw/YYYY-mm-dd/HHMM.json`).**
   Each `collect.sh` execution saves one unmodified JSON bundle at `raw/YYYY-mm-dd/HHMM.json` (UTC) containing the verbatim JSON responses from all four endpoints (`open_meteo`, `openf1_weather`, `openf1_laps`, `openf1_stints`). *(Note: Early manual baseline samples collected on 16–18 Nov 2026 store the single-circuit Las Vegas Open-Meteo JSON response directly at the root; `normalise.sh` handles both formats.)*

## iii. Schema of `data/dataset.csv`

`bin/normalise.sh` builds `data/dataset.csv` from all files in `raw/`.
* **Row grain:** One row = one `Open-Meteo` forecast value set for one circuit and one target hour, as issued in one collection, left-joined on `(circuit_name, valid_time_utc)` with hourly aggregated `OpenF1` track measurements. Only lead times of `0, 24, 48, 72, 96, 120, 144` hours are kept in `dataset.csv` (all 168 hourly values remain preserved in `raw/`). Rows for UTC hours without an F1 session stay empty (`NA`) in the `OpenF1` columns.

| Column | Content | Unit |
| :--- | :--- | :--- |
| `sample_timestamp_utc` | When the sample was collected (taken from `raw/YYYY-mm-dd/HHMM.json`) | ISO-8601 UTC (`YYYY-MM-DDTHH:MM:00Z`) |
| `circuit_name` | Circuit the forecast is for | Text: `Las_Vegas`, `Lusail`, `Yas_Marina` |
| `lead_time_h` | Hours from the collection hour (rounded down) to `valid_time_utc`; only `0, 24, 48, 72, 96, 120, 144` are kept | Hours (integer) |
| `valid_time_utc` | The hour the forecast value is for | ISO-8601 UTC (`YYYY-MM-DDTHH:00:00Z`) |
| `temp_c` | Forecast air temperature at 2 m | `°C` |
| `precip_prob_pct` | Forecast probability of precipitation | `%` (`0–100`) |
| `precip_mm` | Forecast precipitation amount | `mm` |
| `wind_speed_kmh` | Forecast wind speed at 10 m | `km/h` |
| `wind_dir_deg` | Forecast wind direction at 10 m | `°` (`0–360`) |
| `actual_air_temp_c` | Mean measured ambient air temperature during the hour (`OpenF1 /v1/weather`) | `°C` (or `NA`) |
| `actual_track_temp_c` | Mean measured asphalt track temperature during the hour (`OpenF1 /v1/weather`) | `°C` (or `NA`) |
| `actual_wind_speed_kmh` | Mean measured wind speed during the hour, converted from m/s (`× 3.6`) to match `wind_speed_kmh` (`OpenF1 /v1/weather`) | `km/h` (or `NA`) |
| `actual_rainfall` | `1` if any measurement in the hour reported rain, otherwise `0` (`OpenF1 /v1/weather`) | `0/1` (or `NA`) |
| `median_lap_duration_sec` | Median completed lap time during the hour (`OpenF1 /v1/laps`) | Seconds (or `NA`) |
| `dominant_tire_compound` | Most frequent active tire compound during the hour (`OpenF1 /v1/stints`) | Text: `SOFT`, `MEDIUM`, `HARD`, `INTERMEDIATE`, `WET` (or `NA`) |
| `avg_tyre_age_laps` | Mean tire stint age in laps during the hour (`OpenF1 /v1/stints`) | Laps (or `NA`) |

## iv. Why these columns

* **`temp_c`, `precip_prob_pct`, `precip_mm`, `wind_speed_kmh`, `wind_dir_deg`:** Air temperature, rain, and wind shape track grip and cooling, and `OpenF1`'s weather sensors provide direct measured counterparts.
* **`valid_time_utc` and `lead_time_h`:** Identify which hour a forecast targets and how far ahead it was issued, enabling error-vs.-lead-time measurement.
* **`sample_timestamp_utc` and `circuit_name`:** Identify when the forecast was collected and which circuit it applies to.
* **`actual_*` weather, lap, and tire columns:** Provide ground-truth track conditions and session pace/strategy context aggregated to the exact same `(circuit_name, valid_time_utc)` grain.

**Fields omitted from `dataset.csv`:**
* **The `current` block (including relative humidity and surface pressure):** Represents an instantaneous nowcast rather than a multi-day forecast, and our hourly request does not pull hourly humidity or pressure. It remains preserved in `raw/`.
* **Lead times other than `0, 24, ..., 144` h:** All 168 hourly values stay in `raw/`. Keeping every hourly lead time in `dataset.csv` would multiply table size by ~24 with high autocorrelation between adjacent hours.
* **Response metadata (`generationtime_ms`, `utc_offset_seconds`, `timezone`, `timezone_abbreviation`, `elevation`, unit blocks):** Constant or non-analytical; `latitude` and `longitude` are used only to map `circuit_name`.
* **Driver-level rows, mini-sector arrays, and high-frequency car telemetry (`rpm`, `throttle`, `brake`):** Would break the circuit-hour row grain and inflate storage without aiding weather forecast evaluation.

## v. Source fields to schema columns

| Source | Source field | Schema column | Derivation / Notes |
| :--- | :--- | :--- | :--- |
| Raw file path | `raw/YYYY-mm-dd/HHMM.json` | `sample_timestamp_utc` | Parsed from directory and filename (`YYYY-MM-DDTHH:MM:00Z`) |
| `Open-Meteo` | `latitude`, `longitude` | `circuit_name` | Nearest match in circuit lookup table (`circuits.csv`, added with `normalise.sh`) |
| Derived | `valid_time_utc` minus collection hour | `lead_time_h` | Filtered to `0, 24, 48, 72, 96, 120, 144` |
| `Open-Meteo` | `hourly.time[i]` | `valid_time_utc` | GMT = UTC; append `Z` (`i = collection_hour_of_day + lead_time_h`) |
| `Open-Meteo` | `hourly.temperature_2m[i]` | `temp_c` | Direct value |
| `Open-Meteo` | `hourly.precipitation_probability[i]` | `precip_prob_pct` | Direct value |
| `Open-Meteo` | `hourly.precipitation[i]` | `precip_mm` | Direct value |
| `Open-Meteo` | `hourly.wind_speed_10m[i]` | `wind_speed_kmh` | Direct value |
| `Open-Meteo` | `hourly.wind_direction_10m[i]` | `wind_dir_deg` | Direct value |
| `OpenF1 /v1/weather` | `air_temperature` | `actual_air_temp_c` | Hourly mean per circuit |
| `OpenF1 /v1/weather` | `track_temperature` | `actual_track_temp_c` | Hourly mean per circuit |
| `OpenF1 /v1/weather` | `wind_speed` | `actual_wind_speed_kmh` | Hourly mean per circuit, multiplied by `3.6` (`m/s` → `km/h`) |
| `OpenF1 /v1/weather` | `rainfall` | `actual_rainfall` | `1` if any record in the hour has `rainfall > 0`, else `0` |
| `OpenF1 /v1/laps` | `lap_duration` | `median_lap_duration_sec` | Hourly median per circuit (excluding null/pit-out outliers) |
| `OpenF1 /v1/stints` | `compound` | `dominant_tire_compound` | Hourly mode per circuit |
| `OpenF1 /v1/stints` | `tyre_age_at_start` + stint laps | `avg_tyre_age_laps` | Hourly mean per circuit |

## vi. Expected size

* **Assumptions:** 13-week semester (90 days), consisting of ~81 days of hourly collection (`81 × 24 = 1,944` runs) plus ~9 days across the 3 race weekends sampled every 5 minutes (`9 × 288 = 2,592` runs) = **4,536 total runs** (or **2,160 runs** if reverted to hourly all semester after the Las Vegas evaluation). One single-circuit `Open-Meteo` response is **7,424 bytes** (measured on `raw/2026-11-16/1659.json`), so three circuits are **~22,272 bytes** (~21.8 KB) per run.

| Item | Calculation | Size |
| :--- | :--- | :--- |
| `raw/` (`Open-Meteo`, 3 circuits — hourly baseline) | `2,160 × 22,272 B` | ~48.1 MB |
| `raw/` (`Open-Meteo`, 3 circuits — with 3 race weekends at 5-min cadence) | `4,536 × 22,272 B` | ~101.0 MB |
| `raw/` (`OpenF1` 3 endpoints — ~45 KB during active race weekends, ~0.1 KB empty outside) | `(2,592 × 45,000 B) + (1,944 × 100 B)` | ~116.8 MB (or ~15 MB if fetched once post-session) |
| `data/dataset.csv` (3 circuits, 7 lead times) | `4,536 × 3 × 7 = 95,256 rows × ~95 B` | ~9.1 MB (~4.3 MB if hourly all semester) |

Even under continuous 5-minute polling across all three race weekends, total repository storage remains well below half of the 500 MB course limit.

## vii. Limitations

* **`Open-Meteo` rate limits and grid snapping:** The free API is for non-commercial use under 10,000 calls/day (`5,000/hour`, `600/minute`); even 5-minute collection uses only 288 calls/day. Values are gridded model outputs—the coordinates returned in each response snap to the nearest model grid cell (for example, Las Vegas `36.1147, -115.1728` snaps to `36.106308, -115.16396`), not the exact pit-lane sensor location. Times are returned in GMT, which equals UTC.
* **Missed collections:** The live Forecast API keeps only the newest model run, so a missed collection cannot be recovered retroactively. Gaps stay gaps and are not imputed.
* **`OpenF1` historical window and rate limits:** OpenF1 classifies data as live from 30 minutes before a session starts until 30 minutes after it ends; live access requires a paid sponsor account, which we do not use. Outside that window, historical data is free without authentication (up to 3 requests/second and 30/minute) from the 2023 season onward. OpenF1 is an unofficial community project not affiliated with Formula 1.
* **Sparse ground-truth session windows:** Measured circuit telemetry exists only during official F1 sessions (~5 sessions per weekend across the 3 remaining weekends). Because the 2026 F1 season concludes on 6 December, forecasts collected after that date have no `OpenF1` measured counterpart.
* **Las Vegas early-lead coverage:** Forecasts for the 19–21 Nov Las Vegas weekend combine once-daily manual samples collected on 16–18 Nov (providing multi-day lead times) with automated course-server collection starting Thursday, 19 Nov ahead of track action.
* **Hot/arid climate scope limitation:** All three late-season circuits (Las Vegas, Lusail, Yas Marina) are situated in hot, arid desert regions, so forecast-error patterns observed here reflect dry desert conditions rather than year-round European or tropical circuit variability.
