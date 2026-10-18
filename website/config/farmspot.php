<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Report threshold
    |--------------------------------------------------------------------------
    |
    | How many distinct reporters, on open reports (New or Reviewing) against a
    | single target, make that target a "mass report". It only flags the report
    | for an admin to look at; nothing is taken down automatically, because a
    | counter that suspended an account would let any group of buyers bury a
    | competitor.
    |
    | There is deliberately no time window. A window would need a scheduler and
    | would quietly un-flag a target between runs; for a pilot with a few dozen
    | farmers, all open reports counting is both simpler and more honest.
    | Reporting is per subject only: listing reports count against a listing and
    | person reports against the account, never added together.
    |
    */

    'report_threshold' => env('FARMSPOT_REPORT_THRESHOLD', 10),

    /*
    |--------------------------------------------------------------------------
    | Weather widget
    |--------------------------------------------------------------------------
    |
    | The admin dashboard shows a small forecast for the association's area.
    | It uses Open-Meteo, which needs no API key and no account — the panel is
    | read-only decoration and a missing key would only ever mean the widget
    | silently disappears, so a keyless source is the right trade.
    |
    | The coordinates default to Cebu City, where the farms in this pilot
    | cluster; they are env-overridable so another association can point the
    | widget at its own area without a code change. The response is cached so
    | the dashboard never calls the API on every page load, and a failure is
    | swallowed rather than allowed to break the page.
    |
    | Open-Meteo throttles the free endpoint by IP, and a cloud host (Render)
    | shares its egress IP with every other app on the box, so we can be handed
    | a 429 through no fault of our own. The backoff and stale-cache knobs make
    | that a non-event: after a failure we stop calling for a while and show
    | the last good forecast instead of an empty panel.
    |
    */

    'weather' => [
        'enabled' => env('FARMSPOT_WEATHER_ENABLED', true),
        'label' => env('FARMSPOT_WEATHER_LABEL', 'Cebu City, Philippines'),
        'latitude' => (float) env('FARMSPOT_WEATHER_LAT', 10.3157),
        'longitude' => (float) env('FARMSPOT_WEATHER_LNG', 123.8854),
        'timezone' => env('FARMSPOT_WEATHER_TZ', 'Asia/Manila'),
        'endpoint' => 'https://api.open-meteo.com/v1/forecast',
        'days' => (int) env('FARMSPOT_WEATHER_DAYS', 4),
        // Weather does not change faster than this, and a longer window means
        // fewer chances to be throttled.
        'cache_minutes' => (int) env('FARMSPOT_WEATHER_CACHE_MINUTES', 60),
        // After a failed fetch, wait this long before trying Open-Meteo again.
        // Without it every dashboard reload would re-hit an API that already
        // told us to slow down, which only deepens the throttle.
        'backoff_minutes' => (int) env('FARMSPOT_WEATHER_BACKOFF_MINUTES', 10),
        // A successful forecast is kept this long as a last resort, so a 429
        // shows yesterday's still-reasonable numbers instead of nothing.
        'stale_days' => (int) env('FARMSPOT_WEATHER_STALE_DAYS', 7),
        // Open-Meteo asks clients to identify themselves; an anonymous Guzzle
        // user agent is the kind of traffic they throttle hardest.
        'user_agent' => env(
            'FARMSPOT_WEATHER_USER_AGENT',
            'FarmSpot/1.0 (+https://farmspot-api.onrender.com)'
        ),
    ],

];
