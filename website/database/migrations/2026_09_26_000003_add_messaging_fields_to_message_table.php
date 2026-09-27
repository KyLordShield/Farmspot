<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Extends the original `message` table with the one thing a working inbox
 * needs that plain text storage does not: read state.
 *
 * MSG_IS_READ is per message rather than per participant because a thread has
 * exactly two participants, so a single flag is enough and it makes the inbox
 * unread count a plain COUNT instead of a join. A message the author sent is
 * written as read, so the badge only ever counts the other side's messages.
 *
 * The composite index on (CONV_ID, MSG_CREATED_AT) is what makes polling
 * cheap: the app asks for "messages newer than the last one I hold" and
 * MySQL walks this index instead of the table.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->boolean('MSG_IS_READ')->default(0)->after('MSG_CONTENT');
            $table->index(['CONV_ID', 'MSG_CREATED_AT'], 'IDX_MESSAGE_CONVERSATION_TIME');
        });
    }

    public function down(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->dropIndex('IDX_MESSAGE_CONVERSATION_TIME');
            $table->dropColumn('MSG_IS_READ');
        });
    }
};
