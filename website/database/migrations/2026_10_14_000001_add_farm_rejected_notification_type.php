<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Add FARM_REJECTED to the NOTIF_TYPE enum.
 *
 * Same constraints as the whitelist/reactivation migration:
 *
 *  - a new migration rather than an edit to create_notification_table, which
 *    has already run on this database;
 *  - a raw ALTER with the full value list spelled out, since the schema
 *    builder cannot express an enum addition;
 *  - every existing value repeated so the new one is appended, never
 *    substituted.
 *
 * The live enum holds the eleven values below; FARM_REJECTED joins last,
 * keeping new events at the end of the list. The column's comment says
 * "rejection" next to the friendlier wording for the other events because
 * this is the one case where the app does not hide the refusal.
 */
return new class extends Migration
{
    /**
     * The eleven values that were live before this migration.
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
    ];

    /**
     * The one event added by this migration.
     */
    private const NEW_TYPES = [
        'FARM_REJECTED',
    ];

    public function up(): void
    {
        DB::statement(sprintf(
            "ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", array_merge(self::EXISTING_TYPES, self::NEW_TYPES)),
            "'What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation, farm rejection'",
        ));
    }

    public function down(): void
    {
        // Back to exactly the original list. This loses nothing permanent: rows
        // written with FARM_REJECTED while it existed would not fit the narrower
        // enum, so they go first rather than silently truncating to '' and
        // leaving unreadable rows behind.
        DB::statement(sprintf(
            "ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", self::EXISTING_TYPES),
            "'What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation'",
        ));
    }
};