<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One row per enforcement step a moderator applies, so a report can carry more
 * than one and undo walks back through them in order.
 *
 * The previous version kept a single RPT_ACTION column on the report, which
 * capped each report at one action and made a second one a "not allowed"
 * error. That is wrong for the cases that actually come up: a farmer report
 * wants "deactivate this account" and "take down their listings" as two
 * independent, separately reversible decisions, and a listing report wants the
 * listing taken down without also being blocked from deactivating the seller.
 *
 * Nothing is ever deleted here. RAC_PREV holds what to put back, so undo is a
 * restore rather than a rebuild, and RAC_REVERTED_AT keeps the history of an
 * action that was applied and later rolled back.
 */
return new class extends Migration
{
    public function up(): void
    {
        // A failed earlier run can leave the table behind without the migration
        // being recorded, which then makes every retry fail on "already exists".
        Schema::dropIfExists('report_action');

        Schema::create('report_action', function (Blueprint $table) {
            $table->char('RAC_ID', 6)->primary();
            // utf8mb4_general_ci to match the rest of the schema. The legacy
            // tables came from a dump at general_ci while Laravel's default is
            // unicode_ci, and a foreign key between two columns whose collations
            // differ cannot even be created (errno 150).
            $table->char('RPT_ID', 6)->collation('utf8mb4_general_ci');
            $table->string('RAC_ACTION', 40);
            $table->string('RAC_SUBJECT_TYPE', 20)->default('LISTING');
            $table->char('RAC_SUBJECT_ID', 6)->nullable()->collation('utf8mb4_general_ci');
            $table->text('RAC_PREV')->nullable();
            $table->text('RAC_NOTE')->nullable();
            $table->char('RAC_BY', 6)->nullable()->collation('utf8mb4_general_ci');
            $table->dateTime('RAC_APPLIED_AT');
            $table->dateTime('RAC_REVERTED_AT')->nullable();
            $table->char('RAC_REVERTED_BY', 6)->nullable()->collation('utf8mb4_general_ci');

            $table->index('RPT_ID');
            // Undo pops the most recent action that has not been rolled back, so
            // the common lookup is "live actions for this report, newest first".
            $table->index(['RPT_ID', 'RAC_REVERTED_AT'], 'IDX_ACTION_LIVE');
            $table->foreign('RPT_ID')->references('RPT_ID')->on('report')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('report_action');
    }
};
