<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The app's notification inbox.
 *
 * This is deliberately NOT Laravel's standard `notifications` table, which
 * already exists here (added 2026_10_01_000007) and carries the report-action
 * messages. That table is a generic key/value bag: a uuid primary key, a
 * free-text `type`, a JSON `data` blob and nullable timestamps. It works for
 * Laravel's own notify() plumbing, but it cannot answer the two questions this
 * app actually needs to ask:
 *
 *   - "has this farmer already been told about THIS listing?" The app must not
 *     repeat an expiry warning every hour. That needs a real column to match on
 *     (NOTIF_TYPE + NOTIF_REF_ID), not a JSON blob.
 *   - "how many unread does this person have?" A boolean column beats a nullable
 *     timestamp, because read_at = null also means "never rendered".
 *
 * The table is created lowercase (`notification`) to match the schema dump.
 * On Windows this made no difference; on the Linux MySQL the API runs against,
 * table names are case-sensitive, and an uppercase name here meant the model
 * could never find the table.
 *
 * So this table is flat, prefixed like every other table in this schema
 * (NOTIF_), and keys off USR_ID. It is the source of truth: the push that
 * NotificationService also sends is a best-effort extra, and if the phone is
 * offline the row is still waiting when the app next opens.
 *
 * NOTIF_REF_ID points at whatever the notification is about, normally an LST_ID.
 * It is not a foreign key on purpose â€” the same column has to be able to hold a
 * WLST_ID, an RPT_ID or a USR_ID depending on NOTIF_TYPE, and a foreign key
 * spanning four tables cannot be expressed. (report.RPT_TARGET_ID solves the same
 * problem the same way.)
 *
 * There is intentionally no message/chat type here. Chat lives in the separate
 * message table with its own unread badge, and a chat message must never appear
 * in this inbox â€” mixing the two would make the bell unreadable.
 */
return new class extends Migration
{
    /**
     * The event taxonomy. A closed list, not free text: the mobile app switches
     * on this value to decide what icon and what tap behaviour a row gets, so a
     * new word here is a contract change on both sides.
     */
    private const TYPES = [
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

    public function up(): void
    {
        // A failed earlier run can leave the table behind without the migration
        // being recorded, which then makes every retry fail on "already exists".
        // Same guard as the report_action migration.
        Schema::dropIfExists('notification');

        Schema::create('notification', function (Blueprint $table) {
            $table->char('NOTIF_ID', 6)->comment('Unique notification ID');

            // utf8mb4_general_ci to match the legacy dump. The user table came
            // from that dump at general_ci while Laravel's default is
            // unicode_ci, and a foreign key between two columns whose collations
            // differ cannot be created at all (errno 150).
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci')
                ->comment('User the notification is addressed to');

            $table->enum('NOTIF_TYPE', self::TYPES)
                ->comment('What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished');

            $table->string('NOTIF_TITLE', 150)->comment('Short headline shown in the notification list');
            $table->string('NOTIF_BODY', 300)->comment('One short sentence of plain language for the farmer or buyer');

            // The related record, normally an LST_ID. Nullable because some
            // events (a completed setup) have nothing to link back to.
            $table->char('NOTIF_REF_ID', 6)->nullable()->collation('utf8mb4_general_ci')
                ->comment('Related record id (e.g. LST_ID) used for deep-linking and to avoid telling the user twice');

            $table->tinyInteger('NOTIF_IS_READ')->default(0)
                ->comment('Whether the user has opened it (0 or 1)');

            $table->dateTime('NOTIF_CREATED_AT')->comment('When the notification was created');

            $table->primary('NOTIF_ID');

            // The inbox itself: one user's rows, newest first, with the unread
            // ones filterable. The bell badge query is exactly
            // WHERE USR_ID = ? AND NOTIF_IS_READ = 0.
            $table->index(['USR_ID', 'NOTIF_IS_READ'], 'IDX_NOTIFICATION_USER_READ');

            // De-duplication. "Has this user already been told about this
            // listing?" is asked on every hourly run of the expiry commands, and
            // without this it is a full table scan.
            $table->index(['NOTIF_TYPE', 'NOTIF_REF_ID'], 'IDX_NOTIFICATION_TYPE_REF');

            $table->foreign('USR_ID', 'FK_NOTIFICATION_USER')->references('USR_ID')->on('user')
                ->onDelete('cascade')->onUpdate('cascade');
        });

        // Laravel's tinyInteger() emits a bare `tinyint`, which MySQL 8 widens
        // to tinyint(4). The rest of this schema writes the boolean columns as
        // tinyint(1) (farm.FRM_PIN_ACTIVE, message.MSG_IS_READ), and that is a
        // convention worth matching rather than introducing a second one for
        // the same flag. Stated here instead of inline because Blueprint has no
        // display-width argument.
        DB::statement(
            'ALTER TABLE `notification` MODIFY `NOTIF_IS_READ` tinyint(1) NOT NULL DEFAULT 0 '
            ."COMMENT 'Whether the user has opened it (0 or 1)'"
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('notification');
    }
};