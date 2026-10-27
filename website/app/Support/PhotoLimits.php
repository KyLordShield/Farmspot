<?php

namespace App\Support;

use Illuminate\Validation\ValidationException;

class PhotoLimits
{
    public const FARM = 4;

    public const LISTING = 5;

    public static function ensure(int $existing, int $incoming, int $limit, string $kind): void
    {
        if ($existing + $incoming > $limit) {
            throw ValidationException::withMessages([
                'photos' => "A {$kind} can have up to {$limit} photos in total. Remove a photo before adding more.",
            ]);
        }
    }
}
