<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Give report_action timestamps microsecond precision.
 *
 * Undo pops the newest action still in force, and "newest" was read back with
 * ORDER BY RAC_APPLIED_AT DESC. At MySQL's default DATETIME resolution that is
 * one second, so a moderator who applied two steps on the same report in the
 * same second — which is the normal case, since they are two buttons on one
 * page — produced two rows with an identical timestamp. Nothing could break the
 * tie, so undo popped an arbitrary one of the two: taking down a listing and
 * then deactivating its seller, a single undo could restore the listing while
 * leaving the seller deactivated, which is neither of the two things the
 * moderator asked for.
 *
 * Microseconds make the order the order things actually happened in. Separate
 * HTTP requests are never within a microsecond of each other, and a single
 * request only ever applies one action, so this is enough to be deterministic.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('report_action', function (Blueprint $table) {
            $table->dateTime('RAC_APPLIED_AT', 6)->change();
            $table->dateTime('RAC_REVERTED_AT', 6)->nullable()->change();
        });
    }

    public function down(): void
    {
        // Truncating the sub-second part on the way back down would collapse
        // rows that are currently ordered by it, so it is left alone: the
        // columns are widened again rather than rolled back, which is
        // harmless and keeps a reversible migration from being a lossy one.
        Schema::table('report_action', function (Blueprint $table) {
            $table->dateTime('RAC_APPLIED_AT', 6)->change();
            $table->dateTime('RAC_REVERTED_AT', 6)->nullable()->change();
        });
    }
};
