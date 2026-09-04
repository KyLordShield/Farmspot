<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\FarmPhoto;
use App\Models\Whitelist;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class FarmController extends Controller
{
    /**
     * Create a new farm for the authenticated seller candidate.
     *
     * Requires only that the user has a Farmer row (created by the "Become a
     * Seller" step) so they can submit a farm. Whitelist approval is decided
     * here, at submission time: whitelisted users get an instant-approve farm
     * (FRM_STATUS=APPROVED) and have their seller flags flipped, everyone else
     * gets FRM_STATUS=PENDING_REVIEW for admin review. The old
     * FMR_SELLER_MODE_ACTIVE gate is gone because that flag is now only set on
     * this approval path.
     */
    public function store(Request $request)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'Start the seller setup first.',
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

        $isWhitelisted = Whitelist::where('WLST_MOBILE_NUMBER', $user->USR_MOBILE_NUMBER)
            ->where('WLST_IS_ACTIVE', 1)
            ->exists();

        $farmId = $this->uniqueId('farm', 'FRM_ID');

        try {
            $result = DB::transaction(function () use ($validated, $farmId, $farmer, $user, $isWhitelisted) {
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
                    'FRM_PIN_ACTIVE' => $isWhitelisted ? 1 : 0,
                    'FRM_STATUS' => $isWhitelisted ? 'APPROVED' : 'PENDING_REVIEW',
                    'FRM_CREATED_AT' => now(),
                    'FRM_VERIFICATION_DOC_PATH' => $verificationUrl,
                    'FMR_ID' => $farmer->FMR_ID,
                ]);

                if ($isWhitelisted) {
                    $farmer->FMR_SELLER_MODE_ACTIVE = 1;
                    $farmer->FMR_VERIFIED_AT = $farmer->FMR_VERIFIED_AT ?? now();
                    $farmer->save();

                    $user->USR_IS_SELLER = 1;
                    $user->save();
                }

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
            'frm_status' => $isWhitelisted ? 'APPROVED' : 'PENDING_REVIEW',
            'photo_urls' => $result['photo_urls'],
            'verification_document_url' => $result['verification_document_url'],
        ], 201);
    }

    /**
     * List the authenticated seller's own farms.
     * Returns an empty list for users who have no farm yet
     * (e.g. seller mode active but wizard never completed).
     */
    public function index(Request $request)
    {
        $user = $request->user();

        $farms = $user->buyer?->farmer?->farms ?? collect();

        return response()->json([
            'farms' => $farms,
        ]);
    }

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}