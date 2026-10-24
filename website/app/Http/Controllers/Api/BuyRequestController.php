<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BuyRequest;
use App\Support\BuyRequestAccess;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class BuyRequestController extends Controller
{
    public function crops()
    {
        return response()->json(['crops' => collect(config('buy_request_crops'))->map(fn ($aliases, $name) => ['name' => $name, 'aliases' => $aliases])->values()]);
    }

    public function store(Request $request)
    {
        abort_unless($request->user()->USR_IS_PREMIUM, 403, 'Premium is required to post a buy request.');
        $data = $request->validate([
            'crop' => ['required', 'string', Rule::in(array_keys(config('buy_request_crops')))],
            'quantity_kg' => ['required', 'numeric', 'min:0.01', 'max:99999999.99', 'decimal:0,2'],
            'frequency' => ['required', 'in:one-time,weekly'],
            'note' => ['nullable', 'string', 'max:1000'],
            'pickup_location' => ['nullable', 'string', 'max:255'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90', 'required_with:longitude'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180', 'required_with:latitude'],
        ]);
        do {
            $id = strtoupper(Str::random(6));
        } while (BuyRequest::whereKey($id)->exists());
        $row = BuyRequest::create([
            'BRQ_ID' => $id, 'USR_ID' => $request->user()->USR_ID,
            'BRQ_CROP' => trim($data['crop']), 'BRQ_QUANTITY_KG' => $data['quantity_kg'],
            'BRQ_FREQUENCY' => $data['frequency'], 'BRQ_NOTE' => $data['note'] ?? null,
            'BRQ_PICKUP_LOCATION' => $data['pickup_location'] ?? null,
            // Only coordinates explicitly confirmed by the buyer count as a pin.
            'BRQ_LATITUDE' => isset($data['latitude']) ? round($data['latitude'], 7) : null,
            'BRQ_LONGITUDE' => isset($data['longitude']) ? round($data['longitude'], 7) : null,
            'BRQ_HAS_PIN' => isset($data['latitude'], $data['longitude']),
            'BRQ_CREATED_AT' => now(),
        ]);

        return response()->json(['request' => $this->format($row->load('owner'))], 201);
    }

    public function mine(Request $request)
    {
        // Expired subscribers can still view/remove what they previously posted.
        $rows = BuyRequest::with('owner')->withCount('conversations')
            ->where('USR_ID', $request->user()->USR_ID)->whereNull('BRQ_REMOVED_AT')
            ->orderByDesc('BRQ_CREATED_AT')->orderBy('BRQ_ID')->get();

        return response()->json(['requests' => $rows->map(fn ($r) => $this->format($r))->values()]);
    }

    public function index(Request $request)
    {
        $seller = BuyRequestAccess::seller($request->user());
        $search = $request->validate(['search' => ['nullable', 'string', 'max:80']])['search'] ?? null;
        $rows = BuyRequest::with('owner')->withCount('conversations')
            ->whereNull('BRQ_REMOVED_AT')->where('USR_ID', '!=', $request->user()->USR_ID)
            ->whereHas('owner', fn ($q) => $q->where('USR_STATUS', 'ACTIVE'))
            ->when($search, fn ($q) => $q->where('BRQ_CROP', 'like', '%'.$search.'%'))
            ->orderByDesc('BRQ_CREATED_AT')->orderBy('BRQ_ID')->get();
        $results = $rows->map(function ($row) use ($seller) {
            $distances = $seller->farms->filter(fn ($f) => $f->FRM_LATITUDE !== null && $f->FRM_LONGITUDE !== null)
                ->map(fn ($farm) => $row->BRQ_HAS_PIN ? $this->distance($farm->FRM_LATITUDE, $farm->FRM_LONGITUDE, $row->BRQ_LATITUDE, $row->BRQ_LONGITUDE) : null)
                ->filter(fn ($km) => $km !== null);

            return $this->format($row) + ['distance_km' => $distances->isEmpty() ? null : round($distances->min(), 1)];
        })->sortBy(fn ($r) => $r['distance_km'] ?? PHP_FLOAT_MAX)->values();

        return response()->json(['requests' => $results]);
    }

    public function destroy(Request $request, string $id)
    {
        $row = BuyRequest::findOrFail($id);
        abort_unless($row->USR_ID === $request->user()->USR_ID, 403, 'This request is not yours.');
        $row->BRQ_REMOVED_AT ??= now();
        $row->save();

        return response()->json(['message' => 'Request removed. Your existing conversations remain in Messages.']);
    }

    private function format(BuyRequest $row): array
    {
        return [
            'id' => $row->BRQ_ID, 'crop' => $row->BRQ_CROP,
            'quantity_kg' => (float) $row->BRQ_QUANTITY_KG, 'frequency' => $row->BRQ_FREQUENCY,
            'note' => $row->BRQ_NOTE, 'pickup_location' => $row->BRQ_PICKUP_LOCATION,
            'location' => $row->BRQ_HAS_PIN && $row->BRQ_LATITUDE !== null && $row->BRQ_LONGITUDE !== null
                ? ['latitude' => (float) $row->BRQ_LATITUDE, 'longitude' => (float) $row->BRQ_LONGITUDE] : null,
            'created_at' => Carbon::parse($row->BRQ_CREATED_AT)->toIso8601String(),
            'response_count' => (int) ($row->conversations_count ?? 0),
            'buyer' => ['id' => $row->USR_ID, 'name' => $row->owner?->USR_NAME, 'photo' => $row->owner?->USR_PHOTO_PATH, 'phone' => $row->owner?->USR_MOBILE_NUMBER],
        ];
    }

    private function distance($lat1, $lon1, $lat2, $lon2): ?float
    {
        if ($lat2 === null || $lon2 === null) {
            return null;
        }
        $a = sin(deg2rad($lat2 - $lat1) / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin(deg2rad($lon2 - $lon1) / 2) ** 2;

        return 6371 * 2 * asin(sqrt(min(1, max(0, $a))));
    }
}
