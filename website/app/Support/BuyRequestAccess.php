<?php

namespace App\Support;

use App\Models\Farmer;
use App\Models\User;

class BuyRequestAccess
{
    public static function seller(User $user): Farmer
    {
        $farmer = Farmer::whereHas('buyer', fn ($q) => $q->where('USR_ID', $user->USR_ID))
            ->whereHas('farms', fn ($q) => $q->where('FRM_STATUS', 'APPROVED'))
            ->with(['farms' => fn ($q) => $q->where('FRM_STATUS', 'APPROVED')])->first();
        abort_unless($user->isFarmer() && $farmer, 403, 'Only approved sellers can browse and contact buy requests.');

        return $farmer;
    }
}
