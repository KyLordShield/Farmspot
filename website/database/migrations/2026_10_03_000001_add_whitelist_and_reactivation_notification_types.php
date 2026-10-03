<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Add WHITELIST_APPROVED and SELLER_REACTIVATED to the NOTIF_TYPE enum.
 *
 * Why a new migration instead of an edit to create_notification_table:
 * that migration has already run on this database, so editing it changes
 * nothing here and only desynchronises a fresh install from the live schema.
 * Adding a value to a MySQL enum also cannot be expressed with the schema
 * builder's change() - it rewrites the column with the builder's own type
 * guesses - so this is deliberately a raw ALTER with the full value list
 * spelled out. Every existing value is repeated in both directions, so the
 * two new ones are added, never substituted.
 *
 * NOTIFICATION is upper case because that is the table's real name in this
 * legacy schema, where most tables are upper case and prefixed.
 */
return new class extends Migration
{
    /**
     * The nine values that shipped with the original migration.
     */
    private const ORIGINAL_TYPES = [
        'LISTING_EXPIRING_SOON',
        'LISTING_EXPIRED',
        'LISTING_REMOVED',
        'SELLER_DEACTIVATED',
        'ACCOUNT_SUSPENDED',
        'ACCOUNT_REACTIVATED',
        'REPORT_UPDATE',
        'HARVEST_REMINDER',
        'SETUP_COMPLETE',
    ];

    /**
     * The two added by this migration, appended after the originals. Order is
     * meaningful in a MySQL enum: it is the order the admin panel offers when
     * filtering, so new events go last rather than being wedged in the middle.
     */
    private const NEW_TYPES = [
        'WHITELIST_APPROVED',
        'SELLER_REACTIVATED',
    ];

    public function up(): void
    {
        DB::statement(sprintf(
            "ALTER TABLE `NOTIFICATION` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", array_merge(self::ORIGINAL_TYPES, self::NEW_TYPES)),
            "'What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation'",
        ));
    }

    public function down(): void
    {
        // Back to exactly the original list. This loses nothing permanent: rows
        // written with the two new values while they existed would not fit the
        // narrower enum, so they go first rather than silently truncating to ''
        // and leaving unreadable rows behind.
        DB::statement(sprintf(
            "ALTER TABLE `NOTIFICATION` MODIFY `NOTIF_TYPE` ENUM('%s') NOT NULL COMMENT %s",
            implode("','", self::ORIGINAL_TYPES),
            "'What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished'",
        ));
    }
};