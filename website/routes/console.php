<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Listing expiry runs hourly. Both commands are idempotent — they only touch
// rows that still need changing and skip any listing the user has already been
// told about — so a missed hour costs a late warning rather than a duplicate.
Schedule::command('listings:expire')->hourly();

// The 24-hour-ahead warning. Hourly rather than daily because the window is a
// fixed 24 hours: running it once a day would skip listings that entered the
// window between two runs entirely, since the window advances faster than the
// interval it is checked at.
Schedule::command('listings:notify-expiring')->hourly();

// Harvest dates are set per listing by the farmer and checked against "today or
// tomorrow", so this has the same reason to be hourly: a crop that entered the
// two-day window between two daily runs would be missed entirely. It is
// de-duplicated per listing per harvest date, so running it hourly is free -
// the second and third runs find nothing new.
Schedule::command('listings:remind-harvest')->hourly();
