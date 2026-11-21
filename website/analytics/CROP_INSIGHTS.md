# Crop Insights

Flutter displays the insights, Laravel aggregates SQL records and caches the result for five minutes, and Python 3 scores the aggregate counts. The scorer uses only the standard library. The endpoint is `GET /api/insights`. Existing response fields remain available to older app versions.

## Demo setup

On a local, testing, or staging database, apply the migration with `php artisan migrate`. Set `FARMSPOT_INSIGHTS_DEMO=true` and run `php artisan insights:demo` in `website/`. If PHP cannot find Python, set `FARMSPOT_INSIGHTS_PYTHON` to its executable path. The Docker runtime includes Python 3. Rebuild Laravel's config cache if it is enabled.

The command is repeatable and is never called by the application or scheduler. It writes only to `insight_demo_searches` and `insight_demo_listings`, and every row is tagged with a batch ID. Searchers are simulated numeric identities, so the command creates no login accounts. The demo snapshot is pinned to November 21, 2026 in Asia/Manila so the cases remain reproducible. Original weekly search/category cards and seasonal harvest records still use their existing sources.

Undo with `php artisan insights:demo --undo`. The command also clears the demo cache. Turn off demo mode by removing the flag or setting it to `false`. Both the flag and the command are rejected in production.

## Demo edge cases

| Case | Fixture | Expected |
|---|---|---|
| a | Squash has historical interest but no searches in Oct–Nov 2026 | No prediction |
| b | Ginger has no matching-month history and rises in November 2026 | Trending now, Low |
| c | Lettuce has qualifying history only in Nov 2025 and rises in November 2026 | Likely seasonal, Medium |
| d | Tomato has Nov 2023, 2024 and 2025 history with strong November 2026 activity | Seasonal prediction, High |
| e | One simulated person searches for radish 100 times | One searcher, no prediction |
| f | Carrots, corn, cucumber and eggplant each have 12 distinct searchers in the same completed week | Tied counts, ordered by weekly change and then name |
| g | Radish is below the five-searcher threshold | Not enough data |
| h | `  Bok Choy ` and `pechay` | Both contribute to bok choy |
| i | June 2025 is intentionally empty | Zero activity, no invented estimates |
| j | Records include December and January | Manila calendar year transitions apply |
| Supply | Tomato has 95 recent demo searchers and two listings. Squash has zero recent searchers and 24 listings. | Contrasting snapshots |

The main fixture covers Jan 2024 through Nov 2026. A November-only 2023 baseline provides a third prior November. The simulated pool grows from 8 to 40 to 105 distinct searchers. Monthly peaks and deterministic noise vary by crop and period.

## Scoring and verification

A period must reach 30 searches after deduplication and a crop needs five independent searchers in the eligible periods. The proportion is one person per crop divided by all distinct person–crop pairs in that period. A person searching for two crops contributes once to each. Confidence measures supporting evidence, and is not a calibrated probability. Weekly comparisons use two completed Manila weeks.

From `website/`:

- `python -B -m unittest discover -s analytics -p test_search_interest.py`
- `php vendor/bin/phpunit --filter CropSearchInsightsTest`

From `mobile/farmspot_app/`:

- `flutter test test/crop_insights_screen_test.dart`

## Before production

Keep demo mode off. Collect genuine search events with a timestamp, normalized crop term and stable user ID. Preserve enough history for seasonal comparisons and make sure demo or automated activity stays separate. Keep the sample thresholds until real usage supports a change. Review prediction labels against later search activity, verify cold and warm performance on representative MySQL data, and check TalkBack and large text on real devices. The supply comparison uses available listings on the platform; it does not estimate sales, harvest quantities, or farm inventory.

## Three-month search forecast

The forecast covers the next three Manila calendar months. It ranks up to three crops by their average share of app searches during the matching months in the past three years. Each historical month needs 30 distinct person-crop pairs, and a crop needs five distinct searchers in two of those years. The app shows which historical months were used. An empty month means there was too little evidence to forecast. The current-month prediction and harvest-based Seasonal outlook are separate features.

The Python scorer, its tests, and the original three-step analytics pipeline all live in `website/analytics/`. To run the legacy pipeline, change into that folder and use `python run_all.py` with the dependencies in `requirements.txt`.