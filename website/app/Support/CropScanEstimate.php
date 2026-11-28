<?php

namespace App\Support;

use Illuminate\Contracts\Encryption\DecryptException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Validation\ValidationException;

final class CropScanEstimate
{
    public static function issue(string $user, UploadedFile $photo, string $crop, string $condition): string
    {
        return Crypt::encryptString(json_encode([
            'purpose' => self::class,
            'user' => $user,
            'photo' => hash_file('sha256', $photo->getRealPath()),
            'crop' => $crop,
            'condition' => $condition,
            'until' => now()->addHours(2)->timestamp,
        ], JSON_THROW_ON_ERROR));
    }

    public static function days(string $token, string $user, ?UploadedFile $photo, ?string $cropName): int
    {
        try {
            $record = json_decode(Crypt::decryptString($token), true, flags: JSON_THROW_ON_ERROR);
        } catch (DecryptException|\JsonException) {
            $record = null;
        }

        if (($record['purpose'] ?? null) !== self::class
            || $record['user'] !== $user
            || $record['until'] <= now()->timestamp
            || $photo === null
            || $record['photo'] !== hash_file('sha256', $photo->getRealPath())
            || $record['crop'] !== CropShelfLife::detectorName($cropName)) {
            throw ValidationException::withMessages([
                'photo' => ['This photo’s scan is out of date or does not match the crop. Scan it again.'],
            ]);
        }

        $assessment = CropShelfLife::assessment($record['crop'], $record['condition']);
        return $assessment['days'] ?? CropShelfLife::days($cropName);
    }
}
