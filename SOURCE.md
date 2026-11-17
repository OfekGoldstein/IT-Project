# SOURCE.md — F1 Circuit Weather Forecast vs. Historical Track Telemetry

## i. Approved Data Sources

| Name | URL / Endpoint | Data Format | Auth / API Key Required | License | Fixed Sampling Frequency (`cron`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Open-Meteo Forecast API** (Primary Source) | `https://api.open-meteo.com/v1/forecast` | JSON | No | CC BY 4.0 (Open-Source, Non-Commercial) | Fixed hourly (`0 * * * *`) all semester; no calendar branching |
| **OpenF1 Historical Telemetry API** (Integrated Source) | `https://api.openf1.org/v1/weather`, `/v1/laps`, `/v1/stints` | JSON | No for historical sessions (real-time live session streaming requires sponsor-tier authentication and is not used) | Open-Source / Free Public API (Historical Tier) | Fixed daily (`15 0 * * *`) all semester for completed sessions |

## ii. Data Collected from the Sources

We collect two complementary streams of data for Formula 1 circuit locations (starting with Las Vegas, Lusail, and Yas Marina):
1. **Multi-Day Meteorological Forecasts (`Open-Meteo`):** Each hourly pull captures a 168-hour (7-day) forward-looking hourly forecast (`hourly.*`) of air temperature, precipitation probability, precipitation amount, wind speed, and wind direction at the circuit coordinates. Because weather forecasts are overwritten on each model run, these snapshots disappear over time and cannot be retrieved retroactively.
2. **Historical Track Telemetry & Strategy (`OpenF1`):** Completed-session trackside ambient air temperature, asphalt track surface temperature, wind speed, rainfall status (`/v1/weather`), driver lap durations (`/v1/laps`), and tire compound stint records (`/v1/stints`) retrieved after sessions conclude via the unauthenticated historical tier.

## iii. Unified Dataset Schema (`data/dataset.csv`)

* **Table Row Grain:** One row per `(collection_timestamp_utc, target_timestamp_utc, circuit_name)` — i.e., one row for each of the 168 hourly forecast target timestamps issued in a single `Open-Meteo` snapshot, left-joined on `(target_timestamp_utc, circuit_name)` with hourly aggregated historical `OpenF1` track telemetry and session pace/tire metrics (`NA` when no completed F1 session took place during that UTC hour).

| Column Name | Content Description | Units |
| :--- | :--- | :--- |
| `collection_timestamp_utc` | Exact UTC timestamp when the raw file was collected, parsed from `raw/YYYY-mm-dd/HHMM.json` | ISO-8601 (`YYYY-MM-DDTHH:MM:00Z`) |
| `target_timestamp_utc` | Forecasted target hour in UTC (`hourly.time`) | ISO-8601 (`YYYY-MM-DDTHH:00:00Z`) |
| `forecast_lead_hours` | Forecast horizon (`target_timestamp_utc - collection_timestamp_utc`, rounded to nearest hour) | Integer (`hours`, `0–167`) |
| `grid_latitude` | Open-Meteo grid-snapped latitude returned at the JSON root | Decimal degrees (`°`) |
| `grid_longitude` | Open-Meteo grid-snapped longitude returned at the JSON root | Decimal degrees (`°`) |
| `circuit_name` | F1 circuit identifier derived in `normalise.sh` via `±0.05°` bounding-box match on `(grid_latitude, grid_longitude)` | String (e.g., `Las_Vegas`, `Lusail`, `Yas_Marina`) |
| `forecast_air_temp_c` | Forecasted ambient air temperature at 2 meters above ground (`hourly.temperature_2m`) | Degrees Celsius (`°C`) |
| `forecast_precip_prob_pct` | Forecasted probability of precipitation (`hourly.precipitation_probability`) | Percentage (`%`, `0–100`) |
| `forecast_precip_mm` | Forecasted hourly precipitation amount (`hourly.precipitation`) | Millimeters (`mm`) |
| `forecast_wind_speed_kmh` | Forecasted wind speed at 10 meters above ground (`hourly.wind_speed_10m`) | Kilometers per hour (`km/h`) |
| `forecast_wind_dir_deg` | Forecasted wind direction at 10 meters above ground (`hourly.wind_direction_10m`) | Degrees (`0–360°`) |
| `actual_air_temp_c` | Hourly mean measured ambient air temperature at the circuit (`OpenF1 /v1/weather`) | Degrees Celsius (`°C`, or `NA`) |
| `actual_track_temp_c` | Hourly mean measured asphalt track surface temperature (`OpenF1 /v1/weather`) | Degrees Celsius (`°C`, or `NA`) |
| `actual_wind_speed_ms` | Hourly mean measured trackside wind speed (`OpenF1 /v1/weather`) | Meters per second (`m/s`, or `NA`) |
| `actual_rainfall` | Hourly maximum binary indicator of active rainfall on track (`OpenF1 /v1/weather`) | Integer (`0`, `1`, or `NA`) |
| `session_key` | Unique F1 session identifier covering `target_timestamp_utc` (`OpenF1`) | Integer ID (or `NA`) |
| `median_lap_duration_sec` | Median completed driver lap time within `target_timestamp_utc` (`OpenF1 /v1/laps`) | Seconds (`s`, float, or `NA`) |
| `dominant_tire_compound` | Most frequent active Pirelli tire compound during `target_timestamp_utc` (`OpenF1 /v1/stints`) | String (`SOFT`, `MEDIUM`, `HARD`, `INTERMEDIATE`, `WET`, or `NA`) |
| `avg_tyre_age_laps` | Mean tire stint age in laps across active drivers during `target_timestamp_utc` (`OpenF1 /v1/stints`) | Float (`laps`, or `NA`) |

## iv. Justification for Column Selection and Omitted Fields

* **Why these columns were kept:** Retaining all 168 `hourly.*` values together with `collection_timestamp_utc`, `target_timestamp_utc`, and `forecast_lead_hours` enables multi-horizon forecast error analysis (comparing 0-hour to 167-hour predictions against actual historical `OpenF1` trackside sensors). Storing `grid_latitude` and `grid_longitude` with a `±0.05°` bounding-box lookup avoids exact floating-point mismatches caused by Open-Meteo's spatial grid snapping (`36.1147, -115.1728` → `36.106308, -115.16396`). Aggregating `OpenF1` weather, laps, and stints to the circuit-hour level keeps a uniform table grain without sparse per-driver rows.
* **Why other fields were omitted:**
  * From `Open-Meteo`, we omit `current.*` (`current.time`, `current.interval`, `current.temperature_2m`, `current.relative_humidity_2m`, `current.precipitation`, `current.wind_speed_10m`, `current.wind_direction_10m`, `current.surface_pressure`) because they represent instantaneous 15-minute model nowcasts rather than multi-day forecast horizons, as well as static metadata (`generationtime_ms`, `utc_offset_seconds`, `timezone`, `timezone_abbreviation`, `elevation`) and unit-definition objects (`current_units`, `hourly_units`) that are invariant across every pull.
  * From `OpenF1`, we omit individual `driver_number` records (which would break the circuit-hour row grain), mini-sector arrays (`segments_sector_1`, `segments_sector_2`, `segments_sector_3`), and high-frequency car telemetry (`rpm`, `throttle`, `brake`).

## v. Field Name Translation Table

| Source | Original Source Field / Derivation | Schema Column Name (`dataset.csv`) |
| :--- | :--- | :--- |
| File Path | `raw/YYYY-mm-dd/HHMM.json` → `YYYY-MM-DDTHH:MM:00Z` | `collection_timestamp_utc` |
| `Open-Meteo` | `hourly.time` | `target_timestamp_utc` |
| Derived | `(target_timestamp_utc - collection_timestamp_utc)` in hours | `forecast_lead_hours` |
| `Open-Meteo` | `latitude` (root) | `grid_latitude` |
| `Open-Meteo` | `longitude` (root) | `grid_longitude` |
| Derived | Bounding-box lookup (`±0.05°`) on `(grid_latitude, grid_longitude)` | `circuit_name` |
| `Open-Meteo` | `hourly.temperature_2m` | `forecast_air_temp_c` |
| `Open-Meteo` | `hourly.precipitation_probability` | `forecast_precip_prob_pct` |
| `Open-Meteo` | `hourly.precipitation` | `forecast_precip_mm` |
| `Open-Meteo` | `hourly.wind_speed_10m` | `forecast_wind_speed_kmh` |
| `Open-Meteo` | `hourly.wind_direction_10m` | `forecast_wind_dir_deg` |
| `OpenF1 /v1/weather` | `air_temperature` (hourly mean) | `actual_air_temp_c` |
| `OpenF1 /v1/weather` | `track_temperature` (hourly mean) | `actual_track_temp_c` |
| `OpenF1 /v1/weather` | `wind_speed` (hourly mean) | `actual_wind_speed_ms` |
| `OpenF1 /v1/weather` | `rainfall` (hourly max) | `actual_rainfall` |
| `OpenF1` | `session_key` | `session_key` |
| `OpenF1 /v1/laps` | `lap_duration` (hourly median) | `median_lap_duration_sec` |
| `OpenF1 /v1/stints` | `compound` (hourly mode) | `dominant_tire_compound` |
| `OpenF1 /v1/stints` | `tyre_age_at_start` + elapsed stint laps (hourly mean) | `avg_tyre_age_laps` |

## vi. Expected Storage Size Over a Full Semester

* **Measured Single Raw Sample Size:** Based on our initial sample (`raw/2026-11-16/1659.json`), one `Open-Meteo` JSON response is **7,424 bytes** (~7.25 KB). One daily `OpenF1` historical JSON pull (`/v1/weather`, `/v1/laps`, `/v1/stints` for a target session day) is approximately **45,000 bytes** (~43.9 KB).
* **Sampling Volume Across the Semester (13 Weeks = 91 Days):**
  * `Open-Meteo` fixed hourly `cron` runs (`91 days × 24 runs/day = 2,184` files) × `7,424 bytes` = **16,214,016 bytes** (**~16.21 MB**).
  * `OpenF1` fixed daily `cron` runs (`91 days × 1 run/day = 91` files) × `45,000 bytes` = **4,095,000 bytes** (**~4.10 MB**).
* **Total Expected `raw/` Directory Size:** **~20.31 MB** (uncompressed), which is ~4.1% of the 500 MB course limit.
* **Total Expected `data/dataset.csv` Size:** `2,184` `Open-Meteo` snapshots × `168` hourly forecast rows per snapshot = **366,912 rows** × `~115 bytes` per normalized CSV row ≈ **42.19 MB** (combined repository total `raw/` + `data/` ≈ **62.50 MB**, ~12.5% of the 500 MB limit).
