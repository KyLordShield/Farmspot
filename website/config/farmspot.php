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
    */

    'weather' => [
        'enabled' => env('FARMSPOT_WEATHER_ENABLED', true),
        'label' => env('FARMSPOT_WEATHER_LABEL', 'Cebu City, Philippines'),
        'latitude' => (float) env('FARMSPOT_WEATHER_LAT', 10.3157),
        'longitude' => (float) env('FARMSPOT_WEATHER_LNG', 123.8854),
        'timezone' => env('FARMSPOT_WEATHER_TZ', 'Asia/Manila'),
        'endpoint' => 'https://api.open-meteo.com/v1/forecast',
        'days' => (int) env('FARMSPOT_WEATHER_DAYS', 4),
        'cache_minutes' => (int) env('FARMSPOT_WEATHER_CACHE_MINUTES', 30),
    ],

];
