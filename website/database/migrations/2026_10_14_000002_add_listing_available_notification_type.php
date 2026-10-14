<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Add LISTING_AVAILABLE to the NOTIF_TYPE enum.
 *
 * Mirrors the FARM_REJECTED migration: new migration (create script already ran),
 * raw ALTER spelling out the full value list. This powers the automatic flip
 * from SOON_TO_HARVEST to AVAILABLE_NOW.
 */
return new class extends Migration
{
    /**
     * Existing types at the moment of this migration (includes FARM_REJECTED).
     */
    private const EXISTING_TYPES = [
        'LISTING_EXPIRING_SOON',
        'LISTING_EXPIRED',
        'LISTING_REMOVED',
        'SELLER_DEACTIVATED',
        'ACCOUNT_SUSPENDED',
        'ACCOUNT_REACTIVATED',
        'REPORT_UPDATE',
        'HARVEST_REMINDER',
        'SETUP_COMPLETE',
        'WHITELIST_APPROVED',
        'SELLER_REACTIVATED',
        'FARM_REJECTED',
    ];

    private const NEW_TYPES = [
        'LISTING_AVAILABLE',
    ];

    public function up(): void
    {
        DB::statement(sprintf(
            "ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", array_merge(self::EXISTING_TYPES, self::NEW_TYPES)),
            "'What happened: listing expiring/expired/removed/available, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation, farm rejection'"
        ));
    }

    public function down(): void
    {
        DB::statement(sprintf(
            "ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", self::EXISTING_TYPES),
            "'What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation, farm rejection'"
        ));
    }
};
