<?php

return [
    // Explicitly enable on a demo server; off by default outside local/testing.
    'simulation_enabled' => env('PREMIUM_SIMULATION_ENABLED', in_array(env('APP_ENV'), ['local', 'testing'], true)),
];
