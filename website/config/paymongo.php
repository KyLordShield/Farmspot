<?php

return [
    // This integration intentionally supports TEST keys only.
    'enabled' => env('APP_ENV') !== 'testing' && (bool) env('PAYMONGO_TEST_CHECKOUT_ENABLED', false),
    'secret_key' => env('PAYMONGO_SECRET_KEY', ''),
    'webhook_secret' => env('PAYMONGO_WEBHOOK_SECRET', ''),
    'amount' => 9900,
    'currency' => 'PHP',
    'methods' => array_values(array_filter(array_map('trim', explode(',', env('PAYMONGO_TEST_METHODS', 'card,gcash'))))),
    'return_base_url' => env('PAYMONGO_RETURN_BASE_URL', env('APP_URL', 'http://127.0.0.1:8000')),
];
