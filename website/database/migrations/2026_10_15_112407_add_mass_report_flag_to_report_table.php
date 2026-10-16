<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Record when a report cluster was flagged as a mass/important report.
 *
 * A target that collects many reports from many different people is a signal a
 * moderator needs to see, but it is deliberately NOT an automatic takedown: a
 * counter that suspended an account would let any group of buyers bury a
 * competitor. So the threshold only sets this timestamp, the admin queue shows
 * the report as flagged, and a person still decides.
 *
 * The timestamp is set at most once per target. Once any open report for the
 * target carries a value, later reports do not set it again, so the admin is
 * not re-alerted on every new complaint about something already flagged.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('report', function (Blueprint $table) {
            $table->timestamp('RPT_FLAGGED_AT')->nullable()->after('RPT_UPDATED_AT');
        });
    }

    public function down(): void
    {
        Schema::table('report', function (Blueprint $table) {
            $table->dropColumn('RPT_FLAGGED_AT');
        });
    }
};
