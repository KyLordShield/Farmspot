<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Correct farm locations shared before messages stored a farm id.
 *
 * The first version of chat location sharing pinned the seller's current GPS
 * fix and asked them to type a label. Those rows therefore point at wherever
 * the seller stood at the time, which can be far from the farm. When the label
 * exactly names a farm owned by the sender, it was clearly a farm share, so
 * adopt that farm's id and coordinates. Custom labels ("Farm gate") do not
 * match a farm name and are left untouched.
 */
return new class extends Migration
{
    public function up(): void
    {
        $legacy = DB::table('message')
            ->whereNull('MSG_FARM_ID')
            ->whereNotNull('MSG_LATITUDE')
            ->whereNotNull('MSG_LONGITUDE')
            ->whereNotNull('MSG_LOCATION_LABEL')
            ->where('MSG_LOCATION_LABEL', '<>', '')
            ->get(['MSG_ID', 'USR_ID', 'MSG_LOCATION_LABEL']);

        foreach ($legacy as $message) {
            $farm = DB::table('farm')
                ->join('farmer', 'farmer.FMR_ID', '=', 'farm.FMR_ID')
                ->join('buyer', 'buyer.BUY_ID', '=', 'farmer.BUY_ID')
                ->where('buyer.USR_ID', $message->USR_ID)
                ->whereRaw(
                    'LOWER(TRIM(farm.FRM_NAME)) = LOWER(?)',
                    [trim((string) $message->MSG_LOCATION_LABEL)]
                )
                ->first([
                    'farm.FRM_ID',
                    'farm.FRM_LATITUDE',
                    'farm.FRM_LONGITUDE',
                ]);

            if (! $farm) {
                continue;
            }

            DB::table('message')
                ->where('MSG_ID', $message->MSG_ID)
                ->update([
                    'MSG_FARM_ID' => $farm->FRM_ID,
                    'MSG_LATITUDE' => $farm->FRM_LATITUDE,
                    'MSG_LONGITUDE' => $farm->FRM_LONGITUDE,
                ]);
        }
    }

    /**
     * Data correction only. The original GPS fix cannot be distinguished from
     * a genuine farm pin after the update, so rolling back is a no-op.
     */
    public function down(): void
    {
        //
    }
};
