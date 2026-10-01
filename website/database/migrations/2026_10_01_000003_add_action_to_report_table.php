<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What a moderator actually did about a report.
 *
 * Until now the queue could only label a report (New / Reviewing / Resolved /
 * Dismissed), which left the workflow open-ended: a moderator who agreed a
 * listing was fraudulent had no way to take it off sale, so the buyer who
 * reported it saw nothing happen. These columns record the single enforcement
 * step that has been applied, so the queue can show it, and so it can be undone.
 *
 * RPT_ACTION_PREV holds the value to put back on undo, which is why the
 * enforcement column is deliberately narrow. It tracks the CURRENT state of one
 * action, and audit_log is the append-only history of how it got there.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('report', function (Blueprint $table) {
            $table->enum('RPT_ACTION', [
                'NONE',
                'LISTING_TAKEN_DOWN',
                'ACCOUNT_DEACTIVATED',
                'FARMER_UNVERIFIED',
            ])->default('NONE')->after('RPT_UPDATED_AT')
              ->comment('The enforcement step a moderator applied. NONE means the report is still only triaged.');

            $table->dateTime('RPT_ACTION_AT')->nullable()->after('RPT_ACTION')
                  ->comment('When the action was applied, for "taken down 3 days ago".');

            $table->char('RPT_ACTION_BY', 6)->nullable()->after('RPT_ACTION_AT')
                  ->comment('The admin who applied it.');

            // The value to restore on undo: the listing availability, the
            // account status, or the farmer verification timestamp. Kept as a
            // loose varchar because the three targets have different types.
            $table->string('RPT_ACTION_PREV', 50)->nullable()->after('RPT_ACTION_BY')
                  ->comment('Value to restore if the action is undone.');
        });
    }

    public function down(): void
    {
        Schema::table('report', function (Blueprint $table) {
            $table->dropColumn([
                'RPT_ACTION',
                'RPT_ACTION_AT',
                'RPT_ACTION_BY',
                'RPT_ACTION_PREV',
            ]);
        });
    }
};
