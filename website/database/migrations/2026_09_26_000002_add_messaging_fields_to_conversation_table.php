<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The `conversation` and `message` tables already existed in the original
 * capstone schema (buyer <-> farmer threads with plain text messages) but were
 * never implemented. Rather than create competing tables, this migration
 * extends the existing design to what the app needs:
 *
 *   LST_ID   a thread is about one listing, so the same crop cannot open two
 *            threads. Nullable so a database restored from an older dump (where
 *            conversations had no listing) still migrates cleanly; every thread
 *            the app creates sets it.
 *   FRM_ID   copied off the listing so the seller's inbox is one indexed lookup
 *            instead of a join on every poll.
 *   CNV_LAST_MESSAGE / _AT   denormalized inbox preview, so listing the inbox
 *            never needs an N+1 over messages.
 *
 * The unique key on (LST_ID, BUY_ID) is what makes "one thread per listing"
 * true at the database level: a double tap cannot create a duplicate.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('conversation', function (Blueprint $table) {
            $table->char('LST_ID', 6)->nullable()->collation('utf8mb4_general_ci')
                ->after('CONV_ID');
            $table->char('FRM_ID', 6)->nullable()->collation('utf8mb4_general_ci')
                ->after('FMR_ID');
            $table->string('CNV_LAST_MESSAGE', 500)->nullable()
                ->collation('utf8mb4_general_ci')->after('FRM_ID');
            $table->dateTime('CNV_LAST_MESSAGE_AT')->nullable()->after('CNV_LAST_MESSAGE');
            $table->index('LST_ID', 'FK_CONVERSATION_LISTING');
            $table->index('FRM_ID', 'FK_CONVERSATION_FARM');
            $table->index('CNV_LAST_MESSAGE_AT', 'IDX_CONVERSATION_LAST_ACTIVITY');
            $table->foreign('LST_ID')->references('LST_ID')->on('listing')
                ->onDelete('cascade')->onUpdate('cascade');
            $table->foreign('FRM_ID')->references('FRM_ID')->on('farm')
                ->onDelete('cascade')->onUpdate('cascade');
            $table->unique(['LST_ID', 'BUY_ID'], 'UNQ_CONVERSATION_LISTING_BUYER');
        });
    }

    public function down(): void
    {
        Schema::table('conversation', function (Blueprint $table) {
            $table->dropForeign(['LST_ID']);
            $table->dropForeign(['FRM_ID']);
            $table->dropIndex('FK_CONVERSATION_LISTING');
            $table->dropIndex('FK_CONVERSATION_FARM');
            $table->dropIndex('IDX_CONVERSATION_LAST_ACTIVITY');
            $table->dropUnique('UNQ_CONVERSATION_LISTING_BUYER');
            $table->dropColumn(['LST_ID', 'FRM_ID', 'CNV_LAST_MESSAGE', 'CNV_LAST_MESSAGE_AT']);
        });
    }
};
