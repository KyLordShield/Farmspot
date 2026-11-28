<?php

namespace App\Support;

use Illuminate\Support\Str;

final class CropShelfLife
{
    public static function detectorName(?string $name): ?string
    {
        $key = trim(preg_replace('/[^a-z0-9]+/', ' ', Str::lower(Str::ascii($name ?? ''))));

        return match ($key) {
            'kamatis', 'tomato', 'tomatoes' => 'kamatis',
            'lettuce' => 'lettuce',
            'cucumber', 'cucumbers', 'pipino' => 'cucumber',
            'chili', 'chilis', 'chilies', 'chilli', 'chillies', 'sili' => 'chili',
            'green bean', 'green beans', 'baguio beans' => 'green_bean',
            'cabbage', 'cabbages', 'repolyo' => 'cabbage',
            'chayote', 'chayotes', 'sayote' => 'chayote',
            'bok choy', 'pechay', 'pak choi' => 'bok_choy',
            'carrot', 'carrots' => 'carrot',
            default => null,
        };
    }

    // Provisional demo windows, conditional on a scan accepted by the ML service.
    // Deterioration labels have no calibrated remaining-life window.
    public static function assessment(string $crop, ?string $condition): ?array
    {
        [$label, $days] = match ([$crop, $condition]) {
            ['kamatis', 'tomato_unripe'] => ['Looks unripe', 7],
            ['kamatis', 'tomato_ripe'] => ['Looks ripe', 4],
            ['chili', 'chili_unripe'] => ['Looks unripe', 21],
            ['chili', 'chili_ripe'] => ['Looks ripe', 14],
            ['cabbage', 'cabbage_fresh'] => ['Looks fresh', 21],
            ['lettuce', 'lettuce_fresh'] => ['Looks fresh', 7],
            default => [null, null],
        };

        return $label === null ? null : ['label' => $label, 'days' => $days];
    }

    // Use the lower end of the crop's existing typical storage estimate.
    public static function days(?string $name): int
    {
        return match (self::detectorName($name)) {
            'kamatis' => 5,
            'lettuce', 'cucumber', 'bok_choy' => 7,
            'green_bean' => 8,
            'carrot' => 10,
            'chili', 'cabbage' => 21,
            'chayote' => 30,
            default => 3,
        };
    }
}
