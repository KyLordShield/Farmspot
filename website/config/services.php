<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Groq (AI assistant)
    |--------------------------------------------------------------------------
    |
    | The assistant's provider credentials live here and nowhere else — the
    | Flutter app never sees the key, it only ever talks to /api/ai/chat.
    |
    | When the key is missing the assistant degrades to a friendly "unavailable"
    | message instead of erroring, so the rest of the app keeps working.
    |
    */

    'groq' => [
        'key' => env('GROQ_API_KEY'),
        'model' => env('GROQ_MODEL', 'openai/gpt-oss-120b'),
        'base_url' => env('GROQ_BASE_URL', 'https://api.groq.com/openai/v1'),
    ],

    /*
    |--------------------------------------------------------------------------
    | OneSignal (push notifications)
    |--------------------------------------------------------------------------
    |
    | Credentials for the push half of the notification system. Like the Groq
    | key above, these live on the server only — the Flutter app never sees
    | either one, it just registers its push token with OneSignal and reads
    | /api/notifications for the inbox.
    |
    | When either key is blank NotificationService skips the push and writes
    | only the inbox row, so the site keeps working before OneSignal is set up.
    |
    */

    'onesignal' => [
        'app_id' => env('ONESIGNAL_APP_ID'),
        'rest_api_key' => env('ONESIGNAL_REST_API_KEY'),
        'base_url' => env('ONESIGNAL_BASE_URL', 'https://api.onesignal.com'),
    ],

];
