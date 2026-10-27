<?php

namespace App\Support;

use App\Models\Listing;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Str;

class ListingName
{
    public static function key(?string $name): string
    {
        $words = preg_split('/[^a-z0-9]+/', Str::lower(Str::ascii($name ?? '')), -1, PREG_SPLIT_NO_EMPTY);
        $words = array_map(fn ($word) => Str::singular($word), $words);
        sort($words);

        return implode(' ', $words);
    }

    // Caller locks the farm row in its transaction so two submissions cannot
    // both pass the check before either listing has been saved.
    public static function ensureUnique(string $farmId, ?string $name, ?string $exceptId = null): void
    {
        $key = self::key($name);
        if ($key === '') {
            return;
        }

        $existing = Listing::where('FRM_ID', $farmId)
            ->where('LST_AVAILABILITY', '!=', Listing::AVAILABILITY_REMOVED)
            ->when($exceptId, fn ($query) => $query->where('LST_ID', '!=', $exceptId))
            ->pluck('LST_CROP_ICON');

        foreach ($existing as $other) {
            if (self::key($other) === $key) {
                $message = 'This farm already has a listing with the same or a similar crop name. Edit or renew the existing listing instead.';
                throw new HttpResponseException(response()->json([
                    'message' => $message,
                    'errors' => ['crop_icon' => [$message]],
                ], 422));
            }
        }
    }
}
