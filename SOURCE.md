# Project Data Source Proposals

## Proposal 1 (Preferred): F1 Circuit Weather Forecasts vs. Actual Track Conditions
<!-- 
  Why this works: 
  - It pairs a predictive forecast source (Open-Meteo) with an actual telemetry/condition source
  - (OpenF1).
  - Weather forecasts and atmospheric conditions change continuously year-round,
  - making it fully immune to the off-season pause.
-->

* **Essence and Research Question:** Weather conditions (such as track temperature, wind speed,
  and precipitation) heavily influence Formula 1 aerodynamics, tire degradation, and strategy,
  yet rolling weather forecasts change constantly and are overwritten once sessions begin.
  This project compares hourly weather forecasts for F1 circuit coordinates against actual on-track
  weather measurements to analyze forecast convergence error and its impact on racing data.
  **Content:** JSON data containing hourly forecasted air temperature, precipitation probability,
  and wind speed for circuit coordinates, paired with actual track/air temperature sensor logs
  from F1 sessions.
* **URLs:** 
  * Forecast Source: `https://api.open-meteo.com/v1/forecast?latitude=36.1147&longitude=-115.1728&hourly=temperature_2m,precipitation_probability,wind_speed_10m&timezone=UTC`
  * Actual Track Source: `https://api.openf1.org/v1/weather?session_key=latest`
* **Update Frequency:** Forecasts update hourly;
* we will sample every 3 hours (8 times daily) via `cron`.
* **Expected Sample Size:** Approximately 4 KB per sample, yielding roughly 7 MB total
* over the semester (well below the 500MB course limit).
* **API Key / Password Required:** No keys or passwords are required for either public API.

**Data Sample:**
```json
{
  "latitude": 36.106308,
  "longitude": -115.16396,
  "timezone": "GMT",
  "hourly": {
    "time": ["2026-11-04T00:00", "2026-11-04T01:00", "2026-11-04T02:00"],
    "temperature_2m": [19.1, 17.3, 16.2],
    "precipitation_probability": [0, 0, 0],
    "wind_speed_10m": [3.6, 7.1, 11.0]
  }
}
```

## Proposal 2: Specialty Coffee Roasters - Stock and Price Dynamics
<!-- 
  Why this works: 
  - It tracks live micro-lot specialty coffee prices and origin attributes over time,
  - ensuring data is captured dynamically rather than relying on static historical archives.
-->

- **Essence and Research Question:** Online coffee roasters release limited and seasonal coffee lots that sell out or change in price, but a shop only shows its current state; earlier availability and prices are not kept. This project saves the product feeds of two competing Tel Aviv specialty roasters, Nomena and Cafelix. It asks how long coffee lots stay in stock, how often products are added, removed, or repriced, and whether the two roasters sell out similar origins at similar times.
- **Content:** JSON product catalogs: product name, tags and type, price per variant or bag size, regular and sale price, and an in-stock flag. The two shops use different platforms (Shopify and WooCommerce), so field names differ and will be normalized for analysis.
- **URLs:** 
  - Roaster A (Nomena, Shopify product feed): `https://nomenaroasters.com/products.json?limit=250`
  - Roaster B (Cafelix, WooCommerce public Store API): `https://cafelix.co.il/wp-json/wc/store/v1/products?per_page=100`
- **Update Frequency:** Stock and catalog change irregularly. We will sample both once daily via `cron`.
- **Expected Sample Size:** Approximately 500 KB per roaster per sample, yielding roughly 70 MB total over the semester (well below the 500MB course limit).
- **API Key / Password Required:** No keys or passwords are required for the public API tier.

**Data Sample:**
```json
// Cafelix (first product):
{
  "id": 15310,
  "name": "קולומביה – בורבון ורוד H – קלייה בהירה",
  "prices": { "price": "65", "regular_price": "65", "sale_price": "65", "currency_code": "ILS" },
  "on_sale": false
}

// Nomena (first coffee, first variant):
{
  "handle": "uraga",
  "vendor": "NOMENA",
  "product_type": "coffee",
  "tags": ["Single origin"],
  "variants": [{ "title": "פולים שלמים / 250 גרם", "price": "58.00", "available": true }]
}
```
* Our rankings:
  - 1. F1 Circuit Weather Forecasts vs. Actual Track Conditions (Preferred)
    2. Specialty Coffee Roasters - Stock and Price Dynamics (Backup)
