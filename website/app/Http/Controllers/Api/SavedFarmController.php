<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farm;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SavedFarmController extends Controller
{
    private function requirePremium(Request $request): void
    {
        abort_unless($request->user()->USR_IS_PREMIUM, 403, 'Premium is required to use Saved Farms.');
    }

    private function farms()
    {
        return Farm::with(['farmer.buyer.user', 'photos', 'listings' => fn ($q) => $q->with('category')
            ->where('LST_AVAILABILITY', 'ACTIVE')->whereIn('LST_STATUS', ['AVAILABLE_NOW', 'SOON_TO_HARVEST'])]);
    }

    private function visible(Farm $farm): bool
    {
        return $farm->FRM_STATUS === 'APPROVED' && (int) $farm->FRM_PIN_ACTIVE === 1
            && $farm->farmer?->buyer?->user?->USR_STATUS === 'ACTIVE'
            && $farm->farmer?->buyer?->user?->isFarmer();
    }

    public function index(Request $request)
    {
        $this->requirePremium($request);
        $saved = DB::table('saved_farm')->where('USR_ID', $request->user()->USR_ID)
            ->orderByDesc('SAVED_AT')->orderBy('FRM_ID')->get();
        $farms = $this->farms()->whereIn('FRM_ID', $saved->pluck('FRM_ID'))->get()->keyBy('FRM_ID');

        return response()->json(['farms' => $saved->map(function ($row) use ($farms) {
            $farm = $farms->get($row->FRM_ID);

            return $farm && $this->visible($farm) ? $this->format($farm) : [
                'id' => $row->FRM_ID, 'name' => 'Farm unavailable', 'available' => false,
                'available_crops' => [], 'upcoming_crops' => [],
            ];
        })->values()]);
    }

    public function store(Request $request, string $farmId)
    {
        $this->requirePremium($request);
        $farm = $this->farms()->findOrFail($farmId);
        abort_unless($this->visible($farm), 404, 'This farm is not currently available to save.');
        // The composite key makes retries and concurrent saves idempotent.
        DB::table('saved_farm')->insertOrIgnore([
            'USR_ID' => $request->user()->USR_ID, 'FRM_ID' => $farmId, 'SAVED_AT' => now(),
        ]);

        return response()->json(['message' => 'Farm saved.', 'farm' => $this->format($farm)]);
    }

    public function destroy(Request $request, string $farmId)
    {
        // Allow cleanup of one's own saves even after premium ends.
        DB::table('saved_farm')->where('USR_ID', $request->user()->USR_ID)->where('FRM_ID', $farmId)->delete();

        return response()->json(['message' => 'Farm removed from Saved Farms.']);
    }

    private function format(Farm $farm): array
    {
        $photo = $farm->photos->first(fn ($p) => (int) $p->FPHOTO_IS_PRIMARY === 1) ?? $farm->photos->first();
        $names = fn ($status) => $farm->listings->where('LST_STATUS', $status)
            ->map(fn ($l) => trim((string) ($l->LST_CROP_ICON ?: $l->category?->CAT_NAME)))
            ->filter()->unique()->sort()->values();

        return [
            'id' => $farm->FRM_ID, 'name' => $farm->FRM_NAME, 'available' => true,
            'barangay' => $farm->FRM_BARANGAY,
            'latitude' => $farm->FRM_LATITUDE === null ? null : (float) $farm->FRM_LATITUDE,
            'longitude' => $farm->FRM_LONGITUDE === null ? null : (float) $farm->FRM_LONGITUDE,
            'photo_url' => $photo?->FPHOTO_FILE_PATH,
            'available_crops' => $names('AVAILABLE_NOW'), 'upcoming_crops' => $names('SOON_TO_HARVEST'),
        ];
    }
}
