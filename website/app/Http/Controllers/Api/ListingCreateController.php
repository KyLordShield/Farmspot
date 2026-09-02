<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\Listing;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class ListingCreateController extends Controller
{
    /**
     * Create a new crop listing for the authenticated seller.
     * Gated on seller mode being active and the chosen farm belonging
     * to the seller, then creates the Listing row (and optional photo
     * upload) inside a DB transaction.
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
            'farm_id' => ['required', 'string'],
            'category_id' => ['required', 'string', 'exists:crop_category,CAT_ID'],
            'crop_icon' => ['nullable', 'string'],
            'status' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
            'harvest_date' => ['nullable', 'date'],
            'photo' => ['nullable', 'image', 'max:5120'],
        ]);

        $listingId = $this->uniqueId('listing', 'LST_ID');

        try {
            $result = DB::transaction(function () use ($validated, $farmer, $listingId) {
                $farm = Farm::where('FRM_ID', $validated['farm_id'])
                    ->where('FMR_ID', $farmer->FMR_ID)
                    ->first();

                if (! $farm) {
                    throw new HttpResponseException(
                        response()->json([
                            'message' => 'Farm not found or does not belong to you.',
                        ], 403)
                    );
                }

                $imageUrl = null;

                if (isset($validated['photo'])) {
                    $photo = $validated['photo'];
                    $extension = $photo->getClientOriginalExtension() ?: 'jpg';
                    $path = "listing-photos/{$listingId}/" . uniqid() . ".{$extension}";

                    Storage::disk('cloudinary')->put($path, $photo->getRealPath());

                    $imageUrl = Storage::disk('cloudinary')->url($path);
                }

                $expiryDate = now()->addDays(3);

                Listing::create([
                    'LST_ID' => $listingId,
                    'LST_CROP_ICON' => $validated['crop_icon'] ?? null,
                    'LST_STATUS' => $validated['status'],
                    'LST_AVAILABILITY' => 'ACTIVE',
                    'LST_HARVEST_DATE' => $validated['harvest_date'] ?? null,
                    'LST_EXPIRY_DATE' => $expiryDate,
                    'LST_IMAGE' => $imageUrl,
                    'LST_CREATED_AT' => now(),
                    'LST_UPDATED_AT' => now(),
                    'FMR_ID' => $farmer->FMR_ID,
                    'FRM_ID' => $validated['farm_id'],
                    'CAT_ID' => $validated['category_id'],
                ]);

                return [
                    'listing_id' => $listingId,
                    'expiry_date' => $expiryDate,
                    'image_url' => $imageUrl,
                ];
            });
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Failed to create listing.',
            ], 500);
        }

        return response()->json([
            'message' => 'Listing created successfully.',
            'listing_id' => $result['listing_id'],
            'expiry_date' => $result['expiry_date'],
            'image_url' => $result['image_url'],
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