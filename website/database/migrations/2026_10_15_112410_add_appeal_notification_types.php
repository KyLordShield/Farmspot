<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Add APPEAL_APPROVED and APPEAL_DENIED to the NOTIF_TYPE enum.
 *
 * Same constraints as the earlier enum migrations: a new migration rather than
 * an edit to the original, which has already run; a raw ALTER with the full
 * list spelled out, because the schema builder cannot express an enum addition;
 * and every existing value repeated so these are appended, never substituted.
 *
 * The two events are the outcome of a re-evaluation request. A user needs to
 * hear both: an approval means their listing or account is back, and a denial is
 * the final word until something new happens, so leaving them guessing would be
 * worse than a clear no.
 */
return new class extends Migration
{
    /**
     * The thirteen values that were live before this migration.
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
        'LISTING_AVAILABLE',
    ];

    /**
     * The two events added by this migration, appended at the end.
     */
    private const NEW_TYPES = [
        'APPEAL_APPROVED',
        'APPEAL_DENIED',
    ];

    public function up(): void
    {
        DB::statement(sprintf(
            "ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", array_merge(self::EXISTING_TYPES, self::NEW_TYPES)),
            "'What happened: listing expiring/expired/removed/available, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation, farm rejection, appeal outcome'"
        ));
    }

    public function down(): void
    {
        DB::statement(sprintf(
            "ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", self::EXISTING_TYPES),
            "'What happened: listing expiring/expired/removed/available, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation, farm rejection'"
        ));
    }
};
