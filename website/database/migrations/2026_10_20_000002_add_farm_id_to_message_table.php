<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The farm behind a shared chat location.
 *
 * A seller shares a farm, not an arbitrary GPS fix, so the recipient can open
 * the same directions screen a listing uses (which needs the farm id to load
 * the farm's profile and arrival details). The coordinates stay on the message
 * as well: they are what the card renders before a profile fetch, and they let
 * a legacy pin without a farm id keep working.
 *
 * Nullable because a message can still carry a generic pin, and because every
 * message sent before this feature has no farm behind it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->char('MSG_FARM_ID', 6)
                ->nullable()
                ->after('MSG_LOCATION_LABEL');
        });
    }

    public function down(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->dropColumn('MSG_FARM_ID');
        });
    }
};
