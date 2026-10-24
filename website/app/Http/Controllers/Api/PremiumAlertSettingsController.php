<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CropCatalog;
use App\Services\PremiumAlertService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

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
            'push_enabled' => ['sometimes', 'boolean'], 'push_frequency' => ['sometimes', 'in:instant,hourly,daily'],
            'quiet_enabled' => ['sometimes', 'boolean'], 'quiet_start' => ['sometimes', 'date_format:H:i'], 'quiet_end' => ['sometimes', 'date_format:H:i'], 'daily_time' => ['sometimes', 'date_format:H:i'],
            'crop_alerts' => ['sometimes', 'boolean'], 'crops' => ['sometimes', 'array', 'max:50'],
            'crops.*' => ['required', 'string', 'max:100', 'distinct', Rule::in($allowed)],
        ]);
        $crops = array_values($data['crops'] ?? $previous['crops']);
        // Expired accounts can pause/clear their rules, but cannot add crops.
        if (! $request->user()->USR_IS_PREMIUM && array_diff($crops, $previous['crops'])) {
            abort(403, 'Premium is required to add crop alerts.');
        }
        $pushFields = ['PUSH_ENABLED' => 'push_enabled', 'PUSH_FREQUENCY' => 'push_frequency', 'QUIET_ENABLED' => 'quiet_enabled', 'QUIET_START' => 'quiet_start', 'QUIET_END' => 'quiet_end', 'DAILY_TIME' => 'daily_time'];
        $push = [];
        foreach ($pushFields as $column => $field) {
            $push[$column] = $data[$field] ?? $previous[$field];
        }
        if ($push['QUIET_ENABLED'] && $push['QUIET_START'] === $push['QUIET_END']) {
            throw ValidationException::withMessages(['quiet_end' => 'Choose different quiet start and end times.']);
        }
        DB::transaction(function () use ($id, $data, $previous, $crops, $push) {
            DB::table('premium_alert_setting')->upsert([[
                'USR_ID' => $id, 'ALERTS_ENABLED' => $data['enabled'], 'SAVED_FARM_ALERTS' => $data['saved_farms'], 'BUY_REQUEST_ALERTS' => $data['buy_requests'],
                'CROP_ALERTS' => $data['crop_alerts'] ?? $previous['crop_alerts'], 'ALERT_CROPS' => json_encode($crops), ...$push,
            ]], ['USR_ID'], ['ALERTS_ENABLED', 'SAVED_FARM_ALERTS', 'BUY_REQUEST_ALERTS', 'CROP_ALERTS', 'ALERT_CROPS', ...array_keys($push)]);
            if (! $data['enabled'] || ! $push['PUSH_ENABLED']) {
                // Pausing must not cause a burst of old pushes when re-enabled.
                DB::table('premium_push_event')->where('USR_ID', $id)->whereNull('HANDLED_AT')->update(['HANDLED_AT' => now()]);
                DB::table('premium_push_batch')->where('USR_ID', $id)->whereNull('SENT_AT')->whereNull('CANCELLED_AT')->update(['CANCELLED_AT' => now()]);
            }
        });

        return response()->json($this->payload($id, $catalog));
    }
}
