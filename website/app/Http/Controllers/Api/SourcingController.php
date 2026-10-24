<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\Listing;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class SourcingController extends Controller
{
    private function premium(Request $request): void
    {
        abort_unless($request->user()->USR_IS_PREMIUM, 403, 'Premium is required to use Weekly Sourcing.');
    }

    private function publicFarms()
    {
        return Farm::where('FRM_STATUS', 'APPROVED')->where('FRM_PIN_ACTIVE', 1)
            ->whereHas('farmer.buyer.user', fn ($q) => $q->where('USR_STATUS', 'ACTIVE')->where('USR_IS_SELLER', 1));
    }

    private function activeListings()
    {
        return Listing::with('category')->where('LST_AVAILABILITY', 'ACTIVE')->whereIn('LST_STATUS', ['AVAILABLE_NOW', 'SOON_TO_HARVEST'])
            ->whereIn('FRM_ID', $this->publicFarms()->select('FRM_ID'));
    }

    private function normalize(string $name): string
    {
        return preg_replace('/[^a-z0-9]/', '', strtolower(Str::ascii(trim($name))));
    }

    private function catalog(): array
    {
        return app(\App\Services\CropCatalog::class)->all();
    }

    public function show(Request $request)
    {
        $this->premium($request);
        $row = DB::table('weekly_sourcing_list')->where('USR_ID', $request->user()->USR_ID)->first();

        $catalog = $this->catalog();

        return response()->json(['crops' => $row ? json_decode($row->CROPS, true) : [], 'available_crops' => array_keys($catalog), 'crop_aliases' => $catalog]);
    }

    public function update(Request $request)
    {
        $this->premium($request);
        $catalog = $this->catalog();
        // Previously saved custom crops remain valid even when stock disappears.
        $previous = DB::table('weekly_sourcing_list')->where('USR_ID', $request->user()->USR_ID)->value('CROPS');
        $allowed = array_unique([...array_keys($catalog), ...($previous ? json_decode($previous, true) : [])]);
        $data = $request->validate(['crops' => ['present', 'array', 'max:50'], 'crops.*' => ['required', 'string', 'max:100', 'distinct', Rule::in($allowed)]]);
        DB::table('weekly_sourcing_list')->updateOrInsert(['USR_ID' => $request->user()->USR_ID], ['CROPS' => json_encode(array_values($data['crops'])), 'UPDATED_AT' => now()]);

        return response()->json(['crops' => array_values($data['crops'])]);
    }

    public function matches(Request $request)
    {
        $this->premium($request);
        $row = DB::table('weekly_sourcing_list')->where('USR_ID', $request->user()->USR_ID)->first();
        $requested = $row ? json_decode($row->CROPS, true) : [];
        $data = $request->validate([
            'latitude' => ['nullable', 'numeric', 'between:-90,90', 'required_with:longitude'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180', 'required_with:latitude'],
        ]);
        $catalog = $this->catalog();
        $canonical = [];
        foreach ($catalog as $name => $aliases) {
            foreach ([$name, ...$aliases] as $alias) {
                $canonical[$this->normalize($alias)] = $name;
            }
        }
        $requestedByKey = [];
        foreach ($requested as $name) {
            $requestedByKey[$this->normalize($name)] = $name;
        }
        $byFarm = [];
        foreach ($this->activeListings()->get() as $listing) {
            $raw = trim((string) ($listing->LST_CROP_ICON ?: $listing->category?->CAT_NAME));
            $crop = $canonical[$this->normalize($raw)] ?? $raw;
            $selected = $requestedByKey[$this->normalize($crop)] ?? null;
            if ($selected === null) {
                continue;
            }
            $byFarm[$listing->FRM_ID]['crops'][$selected] = true;
            $group = $listing->LST_STATUS === 'AVAILABLE_NOW' ? 'available_crops' : 'upcoming_crops';
            $byFarm[$listing->FRM_ID][$group][$selected] = true;
            $expired = $listing->LST_STATUS === 'AVAILABLE_NOW' && ($listing->LST_EXPIRY_DATE === null || Carbon::parse($listing->LST_EXPIRY_DATE)->isPast());
            $byFarm[$listing->FRM_ID]['needs_confirmation'] = ($byFarm[$listing->FRM_ID]['needs_confirmation'] ?? false) || $expired;
        }
        $covered = [];
        $farms = $this->publicFarms()->whereIn('FRM_ID', array_keys($byFarm))->get()->map(function ($farm) use ($byFarm, &$covered, $data, $requested) {
            $crops = array_values(array_intersect($requested, array_keys($byFarm[$farm->FRM_ID]['crops'])));
            $covered = [...$covered, ...$crops];
            $distance = isset($data['latitude'], $data['longitude']) && $farm->FRM_LATITUDE !== null && $farm->FRM_LONGITUDE !== null
                ? $this->distance((float) $data['latitude'], (float) $data['longitude'], (float) $farm->FRM_LATITUDE, (float) $farm->FRM_LONGITUDE) : null;

            return ['id' => $farm->FRM_ID, 'name' => $farm->FRM_NAME, 'barangay' => $farm->FRM_BARANGAY,
                'latitude' => $farm->FRM_LATITUDE === null ? null : (float) $farm->FRM_LATITUDE,
                'longitude' => $farm->FRM_LONGITUDE === null ? null : (float) $farm->FRM_LONGITUDE,
                'distance_km' => $distance === null ? null : round($distance, 2), 'matched_crops' => $crops,
                'available_crops' => array_keys($byFarm[$farm->FRM_ID]['available_crops'] ?? []),
                'upcoming_crops' => array_keys($byFarm[$farm->FRM_ID]['upcoming_crops'] ?? []),
                'needs_confirmation' => $byFarm[$farm->FRM_ID]['needs_confirmation']];
        })->sortBy(fn ($farm) => [$farm['distance_km'] ?? PHP_FLOAT_MAX, mb_strtolower($farm['name']), $farm['id']])->values();

        return response()->json(['requested_crops' => $requested, 'farms' => $farms, 'missing_crops' => array_values(array_diff($requested, $covered)), 'has_buyer_location' => isset($data['latitude'], $data['longitude'])]);
    }

    private function distance(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $a = sin(deg2rad($lat2 - $lat1) / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin(deg2rad($lon2 - $lon1) / 2) ** 2;

        return 6371 * 2 * asin(sqrt(min(1, max(0, $a))));
    }
}
