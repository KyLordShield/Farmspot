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

];
