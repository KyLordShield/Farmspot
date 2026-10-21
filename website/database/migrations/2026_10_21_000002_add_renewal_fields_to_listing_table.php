<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Record an explicit renewal separately from a normal edit.
 *
 * LST_UPDATED_AT moves on every change, so it cannot tell a buyer whether the
 * crop photo was actually refreshed today or whether the seller only corrected
 * a typo. These two columns make that distinction visible without adding a
 * renewal-history table: the timestamp is the last time the seller renewed with
 * a fresh photo, and the count lets a moderator spot a listing that keeps
 * coming back. Existing rows default to "never renewed" (null / 0), which needs
 * no backfill.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listing', function (Blueprint $table) {
            $table->dateTime('LST_LAST_RENEWED_AT')->nullable()
                ->after('LST_UPDATED_AT')
                ->comment('When the seller last renewed this listing with a fresh photo');

            $table->unsignedSmallInteger('LST_RENEWAL_COUNT')->default(0)
                ->after('LST_LAST_RENEWED_AT')
                ->comment('How many times the seller has renewed this listing');
        });
    }

    public function down(): void
    {
        Schema::table('listing', function (Blueprint $table) {
            $table->dropColumn(['LST_LAST_RENEWED_AT', 'LST_RENEWAL_COUNT']);
        });
    }
};
