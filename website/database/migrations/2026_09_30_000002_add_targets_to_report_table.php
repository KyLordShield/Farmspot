<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Let a report point at a message or a person, not only at a crop listing.
 *
 * The report table shipped with the legacy SQL dump, not a migration, and its
 * shape said "a buyer reported a crop": LST_ID was NOT NULL with a cascading
 * foreign key, and RPT_REASON was a free-text field with no taxonomy behind it.
 * That is a fine model for a marketplace listing and a wrong one for the two
 * other things users need to be able to flag:
 *
 *   - a chat message. The complaint is about something someone SENT, and the
 *     crop the conversation was opened over is not what was objectionable.
 *     Without this a reported message had to be filed against its listing,
 *     which misleads whoever reads the queue.
 *   - a farmer, seller, or another user. A seller account has to be reportable
 *     on its own merits, including a seller whose farm currently has no live
 *     listing to point at.
 *
 * So the table gains a discriminator plus a generic target id, and LST_ID goes
 * nullable. It is deliberately NOT dropped: for a message report the listing is
 * genuinely useful context for a moderator ("was this a sale in progress or an
 * approach out of the blue?"), so it stays filled and indexed.
 *
 * Existing rows are listing reports, which is why every new column either
 * defaults to LISTING or is nullable. No backfill is needed.
 */
return new class extends Migration
{
    /**
     * The reason taxonomy, shared with the mobile app and the admin views.
     *
     * Kept to eight so a person can pick one without reading a wall of text.
     */
    private const REASONS = [
        'MISLEADING_INFO',
        'FAKE_LISTING',
        'HARASSMENT',
        'INAPPROPRIATE_CONTENT',
        'FRAUD_OR_SCAM',
        'SPAM',
        'UNSAFE_BEHAVIOR',
        'OTHER',
    ];

    public function up(): void
    {
        // The FK has to come off before LST_ID can be relaxed to nullable:
        // MySQL will not let a column that participates in a foreign key be
        // redefined while the constraint is in place. It goes back on
        // immediately afterwards, and a NULL LST_ID simply is not a reference
        // at all, so the cascade behaves correctly for the rows that do have
        // one.
        Schema::table('report', function (Blueprint $table) {
            $table->dropForeign('FK_REPORT_LISTING');
        });

        Schema::table('report', function (Blueprint $table) {
            $table->char('LST_ID', 6)->nullable()->collation('utf8mb4_general_ci')->change();

            $table->enum('RPT_TARGET_TYPE', ['LISTING', 'MESSAGE', 'FARMER', 'USER'])
                ->default('LISTING')
                ->comment('What was reported: a crop listing, a chat message, a farmer/seller account, or a plain user account.');

            $table->char('RPT_TARGET_ID', 6)->nullable()->collation('utf8mb4_general_ci')
                ->comment('Primary key of the reported thing in its own table: LST_ID, MSG_ID, FMR_ID or USR_ID. No foreign key, since it spans four tables.');

            $table->enum('RPT_REASON_CODE', self::REASONS)->default('OTHER')
                ->comment('The taxonomy value. RPT_REASON keeps the human-readable label for the existing admin search and tables.');

            $table->text('RPT_DETAILS')->nullable()
                ->comment('Optional free text the reporter typed in the app.');

            $table->dateTime('RPT_UPDATED_AT')->nullable()
                ->comment('When a moderator last changed the status, for "how long has this been open".');

            $table->index('RPT_TARGET_TYPE', 'FK_REPORT_TARGET_TYPE');
            $table->index('RPT_TARGET_ID', 'FK_REPORT_TARGET_ID');

            // The moderator queue's default view is "newest first, unhandled".
            $table->index(['RPT_STATUS', 'RPT_CREATED_AT'], 'IDX_REPORT_STATUS_CREATED');
        });

        Schema::table('report', function (Blueprint $table) {
            // Named explicitly: dropping and re-adding the constraint makes
            // Laravel fall back to its own report_lst_id_foreign naming, which
            // would no longer match the name recorded in mysql-schema.sql.
            $table->foreign('LST_ID', 'FK_REPORT_LISTING')->references('LST_ID')->on('listing')
                ->onDelete('cascade')->onUpdate('cascade');
        });

        // Backfill the discriminator for anything already in the table. A
        // listing report is the only kind the old schema could express, and
        // RPT_TARGET_ID is its listing id.
        DB::table('report')
            ->whereNull('RPT_TARGET_ID')
            ->update(['RPT_TARGET_TYPE' => 'LISTING', 'RPT_TARGET_ID' => DB::raw('LST_ID')]);
    }

    /**
     * Revert to the listing-only shape.
     *
     * Reports that are not about a listing have to go first: LST_ID is NOT NULL
     * again on the way down, and re-pointing them at some arbitrary listing
     * would be worse than losing them, since it would put a message report in
     * front of a moderator as a crop complaint.
     */
    public function down(): void
    {
        DB::table('report')->where('RPT_TARGET_TYPE', '!=', 'LISTING')->delete();
        DB::table('report')->whereNull('LST_ID')->delete();

        Schema::table('report', function (Blueprint $table) {
            $table->dropForeign('FK_REPORT_LISTING');
        });

        Schema::table('report', function (Blueprint $table) {
            $table->char('LST_ID', 6)->nullable(false)->collation('utf8mb4_general_ci')->change();
            $table->dropIndex('FK_REPORT_TARGET_TYPE');
            $table->dropIndex('FK_REPORT_TARGET_ID');
            $table->dropIndex('IDX_REPORT_STATUS_CREATED');
            $table->dropColumn(['RPT_TARGET_TYPE', 'RPT_TARGET_ID', 'RPT_REASON_CODE', 'RPT_DETAILS', 'RPT_UPDATED_AT']);
        });

        Schema::table('report', function (Blueprint $table) {
            $table->foreign('LST_ID', 'FK_REPORT_LISTING')->references('LST_ID')->on('listing')
                ->onDelete('cascade')->onUpdate('cascade');
        });
    }
};
