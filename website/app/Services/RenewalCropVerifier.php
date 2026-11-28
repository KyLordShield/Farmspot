<?php

namespace App\Services;

use App\Support\CropShelfLife;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Pool;
use Illuminate\Http\Client\Response;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Validation\ValidationException;

final class RenewalCropVerifier
{
    /** @param array<string, UploadedFile> $photos */
    public function verifyListingPhotos(array $photos, ?string $cropName): void
    {
        $expectedCrop = CropShelfLife::detectorName($cropName);
        if ($expectedCrop === null) {
            throw ValidationException::withMessages([
                'photos' => ['The scanner cannot verify photos for this listing’s crop.'],
            ]);
        }
        $this->verify($photos, $expectedCrop);
    }

    /** @param array<string, UploadedFile> $photos */
    public function verify(array $photos, string $expectedCrop): array
    {
        $url = config('services.image_detect.url');
        $token = config('services.image_detect.token');
        if (!$url || !$token) {
            abort(503, 'Crop verification is unavailable. Try again later.');
        }

        try {
            $responses = Http::pool(function (Pool $pool) use ($photos, $token, $url) {
                $requests = [];
                foreach ($photos as $field => $photo) {
                    $requests[] = $pool->as($field)->withToken($token)->acceptJson()
                        ->connectTimeout(15)->timeout(150)
                        ->attach('file', file_get_contents($photo->getRealPath()), 'crop.'.$photo->extension())
                        ->post(rtrim($url, '/').'/detect?include_condition=true');
                }

                return $requests;
            });
        } catch (ConnectionException) {
            abort(503, 'Crop verification took too long. Try again.');
        }

        $estimates = [];
        foreach (array_keys($photos) as $field) {
            $response = $responses[$field] ?? null;
            if (!$response instanceof Response || !$response->successful()) {
                abort(503, 'Crop verification is unavailable. Try again later.');
            }
            $detections = $response->json('detections');
            if (!is_array($detections)) {
                abort(503, 'Crop verification is unavailable. Try again later.');
            }
            $estimates[$field] = $this->verifiedDays($detections, $expectedCrop, $field);
        }
        return $estimates;
    }

    private function verifiedDays(array $detections, string $expectedCrop, string $field): ?int
    {
        // A listing gallery must clearly show the crop from the listing.
        // Mixed or unidentified photos should be retaken with just that crop.
        if (count($detections) !== 1 || ($detections[0]['name'] ?? null) !== $expectedCrop) {
            throw ValidationException::withMessages([
                $field => ['Retake this photo with only the crop named on the listing clearly visible.'],
            ]);
        }

        $assessment = CropShelfLife::assessment($expectedCrop, $detections[0]['condition'] ?? null);
        return $assessment['days'] ?? null;
    }
}
