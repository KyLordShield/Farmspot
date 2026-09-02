<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\FarmPhoto;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class FarmController extends Controller
{
    /**
     * Create a new farm for the authenticated seller.
     * Gated on the user's Farmer record having seller mode active,
     * then creates the Farm row and uploads its photos to Cloudinary,
     * all inside a DB transaction.
     */
    public function store(Request $request)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer || (int) $farmer->FMR_SELLER_MODE_ACTIVE !== 1) {
            return response()->json([
                'message' => 'Seller mode not active.',
            ], 403);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string'],
            'barangay' => ['required', 'string', 'max:100'],
            'latitude' => ['required', 'numeric'],
            'longitude' => ['required', 'numeric'],
            'photos' => ['required', 'array', 'min:1'],
            'photos.*' => ['image', 'max:5120'],
            'verification_document' => ['nullable', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:5120'],
        ]);

        $farmId = $this->uniqueId('farm', 'FRM_ID');

        try {
            $result = DB::transaction(function () use ($validated, $farmId, $farmer) {
                $verificationUrl = null;

                if (isset($validated['verification_document'])) {
                    $doc = $validated['verification_document'];
                    $extension = $doc->getClientOriginalExtension() ?: 'jpg';
                    $path = "farm-verification/{$farmId}/" . uniqid() . ".{$extension}";

                    Storage::disk('cloudinary')->put($path, $doc->getRealPath());

                    $verificationUrl = Storage::disk('cloudinary')->url($path);
                }

                $farm = Farm::create([
                    'FRM_ID' => $farmId,
                    'FRM_NAME' => $validated['name'],
                    'FRM_DESCRIPTION' => $validated['description'] ?? null,
                    'FRM_BARANGAY' => $validated['barangay'],
                    'FRM_LATITUDE' => $validated['latitude'],
                    'FRM_LONGITUDE' => $validated['longitude'],
                    'FRM_PIN_ACTIVE' => 1,
                    'FRM_CREATED_AT' => now(),
                    'FRM_VERIFICATION_DOC_PATH' => $verificationUrl,
                    'FMR_ID' => $farmer->FMR_ID,
                ]);

                $urls = [];

                foreach ($validated['photos'] as $photo) {
                    $extension = $photo->getClientOriginalExtension() ?: 'jpg';
                    $path = "farm-photos/{$farmId}/" . uniqid() . ".{$extension}";

                    Storage::disk('cloudinary')->put($path, $photo->getRealPath());

                    $url = Storage::disk('cloudinary')->url($path);

                    FarmPhoto::create([
                        'FPHOTO_ID' => $this->uniqueId('farm_photo', 'FPHOTO_ID'),
                        'FPHOTO_FILE_PATH' => $url,
                        'FPHOTO_UPLOADED_AT' => now(),
                        'FRM_ID' => $farm->FRM_ID,
                    ]);

                    $urls[] = $url;
                }

                return [
                    'photo_urls' => $urls,
                    'verification_document_url' => $verificationUrl,
                ];
            });
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Failed to create farm.',
            ], 500);
        }

        return response()->json([
            'message' => 'Farm created successfully.',
            'farm_id' => $farmId,
            'photo_urls' => $result['photo_urls'],
            'verification_document_url' => $result['verification_document_url'],
        ], 201);
    }

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}