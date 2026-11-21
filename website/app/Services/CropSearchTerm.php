<?php

namespace App\Services;

final class CropSearchTerm
{
    public static function normalize(string $crop): string
    {
        $crop = mb_strtolower(trim(preg_replace('/\s+/u', ' ', $crop) ?? $crop));
        return match ($crop) {
            'pechay', 'bokchoy', 'pak choi' => 'bok choy',
            'sitaw', 'yardlong beans' => 'string beans',
            'ampalaya' => 'bitter melon',
            'kamote' => 'sweet potato',
            'kamatis' => 'tomato',
            default => $crop,
        };
    }
}
