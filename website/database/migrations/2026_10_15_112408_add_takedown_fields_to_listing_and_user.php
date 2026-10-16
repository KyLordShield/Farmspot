<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The reason a listing or an account was taken down, so the owner can contest it.
 *
 * A takedown used to leave no trace on the thing it removed. The owner could see
 * their listing gone from the feed or their login refused, with no reason at all
 * and no way to ask for a second look. These columns make the takedown a fact
 * the app can act on:
 *
 *   - *_TAKEDOWN_REASON is the moderator's note. It is what the app shows the
 *     owner, and it is the marker that distinguishes "taken down by us" from a
 *     farmer simply deleting their own listing (which leaves no reason).
 *   - *_TAKEDOWN_AT is when it happened. An appeal is only final until the NEXT
 *     takedown, so a denial is compared against this: a fresh takedown after a
 *     denial re-opens the right to appeal.
 *   - *_HIDDEN_BY_TAKEDOWN remembers which rows the takedown itself hid.
 *     Restoring an account must bring back only the listings we took down, never
 *     ones the farmer had already deleted for their own reasons.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listing', function (Blueprint $table) {
            $table->string('LST_TAKEDOWN_REASON', 500)->nullable()->after('LST_DESCRIPTION');
            $table->timestamp('LST_TAKEDOWN_AT')->nullable()->after('LST_TAKEDOWN_REASON');
            $table->boolean('LST_HIDDEN_BY_TAKEDOWN')->default(false)->after('LST_TAKEDOWN_AT');
        });

        Schema::table('user', function (Blueprint $table) {
            $table->string('USR_TAKEDOWN_REASON', 500)->nullable()->after('USR_STATUS');
            $table->timestamp('USR_TAKEDOWN_AT')->nullable()->after('USR_TAKEDOWN_REASON');
            $table->boolean('USR_HIDDEN_BY_TAKEDOWN')->default(false)->after('USR_TAKEDOWN_AT');
        });
    }

    public function down(): void
    {
        Schema::table('listing', function (Blueprint $table) {
            $table->dropColumn(['LST_TAKEDOWN_REASON', 'LST_TAKEDOWN_AT', 'LST_HIDDEN_BY_TAKEDOWN']);
        });

        Schema::table('user', function (Blueprint $table) {
            $table->dropColumn(['USR_TAKEDOWN_REASON', 'USR_TAKEDOWN_AT', 'USR_HIDDEN_BY_TAKEDOWN']);
        });
    }
};
