# SOURCE.md — F1 Circuit Weather Forecast vs. Live Track Telemetry

## i. Approved Data Sources

| Name | URL / Endpoint | Data Format | Auth / API Key Required | License | Sampling Frequency |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Open-Meteo Forecast API** (Primary Source) | `https://api.open-meteo.com/v1/forecast` | JSON | No | CC BY 4.0 (Open-Source, Non-Commercial) | Every 15 minutes during race weeks / hourly on off-weeks |
| **OpenF1 Live Telemetry API** (Integrated Source) | `https://api.openf1.org/v1/weather`, `/v1/laps`, `/v1/stints` | JSON | No | Open-Source / Free Public API | Every 5–15 minutes during active F1 sessions |

## ii. Data Collected from the Sources

We collect two complementary streams of data around Formula 1 Grand Prix weekends (starting with the Las Vegas, Qatar, and Abu Dhabi GPs and post-season testing):
1. **Meteorological Forecasts (`Open-Meteo`):** Current and hourly forecasted air temperature, relative humidity, surface air pressure, precipitation probability, precipitation amount, wind speed, and wind direction at the exact GPS coordinates of the active F1 circuit. Because weather forecasts are overwritten with each model run, these snapshots disappear over time and cannot be retrieved retroactively.
2. **Live Track Telemetry & Strategy (`OpenF1`):** Real-time track surface temperature, ambient air temperature, wind speed, rainfall status, driver lap times (`/laps`), and tire compound stint data (`/stints`) recorded during official F1 sessions.

## iii. Unified Dataset Schema (`data/dataset.csv`)

All raw JSON snapshots are normalized into a single flat table (`data/dataset.csv`) with the following columns:

| Column Name | Content Description | Units |
| :--- | :--- | :--- |
| `sample_timestamp_utc` | Exact UTC timestamp when the sample was collected | ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`) |
| `circuit_name` | Name of the Formula 1 circuit being sampled | String (e.g., `Las_Vegas`, `Lusail`, `Yas_Marina`) |
| `forecast_air_temp_c` | Forecasted ambient air temperature at 2 meters above ground (`Open-Meteo`) | Degrees Celsius (`°C`) |
| `forecast_humidity_pct` | Forecasted relative humidity at 2 meters (`Open-Meteo`) | Percentage (`%`, `0–100`) |
| `forecast_precip_mm` | Forecasted precipitation amount (`Open-Meteo`) | Millimeters (`mm`) |
| `forecast_precip_prob_pct` | Forecasted probability of precipitation (`Open-Meteo`) | Percentage (`%`, `0–100`) |
| `forecast_wind_speed_kmh` | Forecasted wind speed at 10 meters above ground (`Open-Meteo`) | Kilometers per hour (`km/h`) |
| `forecast_wind_dir_deg` | Forecasted wind direction at 10 meters (`Open-Meteo`) | Degrees (`0–360°`) |
| `forecast_pressure_hpa` | Forecasted atmospheric surface pressure (`Open-Meteo`) | Hectopascals (`hPa`) |
| `actual_air_temp_c` | Measured ambient air temperature at the circuit (`OpenF1`) | Degrees Celsius (`°C`) |
| `actual_track_temp_c` | Measured asphalt track surface temperature (`OpenF1`) | Degrees Celsius (`°C`) |
| `actual_wind_speed_ms` | Measured trackside wind speed (`OpenF1`) | Meters per second (`m/s`) |
| `actual_rainfall` | Binary/numeric indicator of active rainfall on track (`OpenF1`) | Boolean / Integer (`0` or `1`) |
| `session_key` | Unique F1 session identifier (`OpenF1`) | Integer ID |
| `driver_number` | FIA car number of the sampled driver (`OpenF1`) | Integer (`1–99`) |
| `lap_duration_sec` | Completed lap time duration (`OpenF1`) | Seconds (`s`, float) |
| `tire_compound` | Active Pirelli tire compound during the stint (`OpenF1`) | Categorical String (`SOFT`, `MEDIUM`, `HARD`, `INTERMEDIATE`, `WET`) |
| `tyre_age_laps` | Number of laps completed on the current set of tires (`OpenF1`) | Integer (`laps`) |

## iv. Justification for Column Selection and Omitted Fields

- **Why these columns were kept:** The selected fields allow us to (1) directly evaluate `Open-Meteo` forecast accuracy against actual `OpenF1` trackside sensors (air temperature, wind, precipitation), and (2) quantify how wind gusts and track temperature shifts affect car pace (`lap_duration_sec`) and tire degradation (`tire_compound`, `tyre_age_laps`).
- **Why other fields were omitted:**
  - From `Open-Meteo`, we omit metadata fields (`generationtime_ms`, `utc_offset_seconds`, `elevation`, and unit-definition objects like `current_units` / `hourly_units`) because they are static across every pull and add redundant bloat to `dataset.csv`.
  - From `OpenF1`, we omit high-frequency mini-sector arrays (`segments_sector_1`, `segments_sector_2`, `segments_sector_3`) and raw car telemetry (`rpm`, `throttle`, `brake`), as they are not needed for macro weather-strategy correlation and would unnecessarily inflate storage size.

## v. Field Name Translation Table

| Source | Original Source Field Path (JSON) | Schema Column Name (`dataset.csv`) |
| :--- | :--- | :--- |
| `Open-Meteo` | `current.time` / `hourly.time` | `sample_timestamp_utc` |
| `Open-Meteo` | `current.temperature_2m` | `forecast_air_temp_c` |
| `Open-Meteo` | `current.relative_humidity_2m` | `forecast_humidity_pct` |
| `Open-Meteo` | `current.precipitation` | `forecast_precip_mm` |
| `Open-Meteo` | `hourly.precipitation_probability` | `forecast_precip_prob_pct` |
| `Open-Meteo` | `current.wind_speed_10m` | `forecast_wind_speed_kmh` |
| `Open-Meteo` | `current.wind_direction_10m` | `forecast_wind_dir_deg` |
| `Open-Meteo` | `current.surface_pressure` | `forecast_pressure_hpa` |
| `OpenF1` | `date` / `session_key` | `sample_timestamp_utc` / `session_key` |
| `OpenF1` | `air_temperature` | `actual_air_temp_c` |
| `OpenF1` | `track_temperature` | `actual_track_temp_c` |
| `OpenF1` | `wind_speed` | `actual_wind_speed_ms` |
| `OpenF1` | `rainfall` | `actual_rainfall` |
| `OpenF1` | `driver_number` | `driver_number` |
| `OpenF1` | `lap_duration` | `lap_duration_sec` |
| `OpenF1` | `compound` | `tire_compound` |
| `OpenF1` | `tyre_age_at_start` + lap offset | `tyre_age_laps` |

## vi. Expected Storage Size Over a Full Semester

- **Single Raw Sample Size:** One `Open-Meteo` JSON response is approximately **6 KB**, and an active session `OpenF1` snapshot (weather + latest stint/lap summary) is approximately **25 KB–40 KB**.
- **Sampling Volume Across the Semester (13 Weeks):**
  - Sampling `Open-Meteo` hourly (24 samples/day × 90 days = 2,160 files) × 6 KB ≈ **13 MB**.
  - Sampling `OpenF1` + `Open-Meteo` every 5 minutes during ~25 hours of live track sessions (300 high-frequency samples × 40 KB) ≈ **12 MB**.
- **Total Expected `raw/` Directory Size:** **~25 MB** (uncompressed), which is 5% of the 500 MB course limit.
- **Total Expected `data/dataset.csv` Size:** Approximately 15,000–25,000 normalized CSV rows × ~120 bytes per row ≈ **2 MB–3 MB**.
