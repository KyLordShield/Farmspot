<?php

namespace App\Observers;

use App\Models\BuyRequest;
use App\Services\PremiumAlertService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class PremiumBuyRequestObserver
{
    public function created(BuyRequest $request): void
    {
        $id = $request->BRQ_ID;
        DB::afterCommit(function () use ($id) {
            try {
                app(PremiumAlertService::class)->requestCreated($id);
            } catch (\Throwable $e) {
                Log::error('Buy request alert failed', ['request' => $id, 'error' => $e->getMessage()]);
            }
        });
    }
}
