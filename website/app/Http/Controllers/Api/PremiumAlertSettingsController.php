<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CropCatalog;
use App\Services\PremiumAlertService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class PremiumAlertSettingsController extends Controller
{
    private function payload(string $userId, array $catalog): array
    {
        return PremiumAlertService::settings($userId) + ['available_crops' => array_keys($catalog), 'crop_aliases' => $catalog];
    }

    public function show(Request $request)
    {
        return response()->json($this->payload($request->user()->USR_ID, app(CropCatalog::class)->all()));
    }

    public function update(Request $request)
    {
        $id = $request->user()->USR_ID;
        $previous = PremiumAlertService::settings($id);
        $catalog = app(CropCatalog::class)->all();
        $allowed = array_unique([...array_keys($catalog), ...$previous['crops']]);
        $data = $request->validate([
            'enabled' => ['required', 'boolean'], 'saved_farms' => ['required', 'boolean'], 'buy_requests' => ['required', 'boolean'],
            'crop_alerts' => ['sometimes', 'boolean'], 'crops' => ['sometimes', 'array', 'max:50'],
            'crops.*' => ['required', 'string', 'max:100', 'distinct', Rule::in($allowed)],
        ]);
        $crops = array_values($data['crops'] ?? $previous['crops']);
        // Expired accounts can pause/clear their rules, but cannot add crops.
        if (! $request->user()->USR_IS_PREMIUM && array_diff($crops, $previous['crops'])) {
            abort(403, 'Premium is required to add crop alerts.');
        }
        DB::table('premium_alert_setting')->upsert([[
            'USR_ID' => $id, 'ALERTS_ENABLED' => $data['enabled'], 'SAVED_FARM_ALERTS' => $data['saved_farms'], 'BUY_REQUEST_ALERTS' => $data['buy_requests'],
            'CROP_ALERTS' => $data['crop_alerts'] ?? $previous['crop_alerts'], 'ALERT_CROPS' => json_encode($crops),
        ]], ['USR_ID'], ['ALERTS_ENABLED', 'SAVED_FARM_ALERTS', 'BUY_REQUEST_ALERTS', 'CROP_ALERTS', 'ALERT_CROPS']);

        return response()->json($this->payload($id, $catalog));
    }
}
