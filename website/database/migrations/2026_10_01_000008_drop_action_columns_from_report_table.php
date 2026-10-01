<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Remove the single-action columns, now superseded by the report_action table.
 *
 * RPT_ACTION/RPT_ACTION_AT/RPT_ACTION_BY/RPT_ACTION_PREV could only ever hold
 * one action per report, so a farmer report could not be both deactivated and
 * have their listings taken down, and a second attempt was an error rather
 * than a second decision. report_action holds the same information as an
 * append-only list, which is why these are no longer needed.
 */
return new class extends Migration
{
    public function up(): void
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

    public function down(): void
    {
        Schema::table('report', function (Blueprint $table) {
            $table->enum('RPT_ACTION', [
                'NONE',
                'LISTING_TAKEN_DOWN',
                'ACCOUNT_DEACTIVATED',
                'FARMER_UNVERIFIED',
            ])->default('NONE')->after('RPT_UPDATED_AT');

            $table->dateTime('RPT_ACTION_AT')->nullable()->after('RPT_ACTION');
            $table->char('RPT_ACTION_BY', 6)->nullable()->after('RPT_ACTION_AT');
            $table->string('RPT_ACTION_PREV', 50)->nullable()->after('RPT_ACTION_BY');
        });
    }
};
