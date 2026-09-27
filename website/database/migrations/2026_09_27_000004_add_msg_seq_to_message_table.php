<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gives every message a monotonic sequence number.
 *
 * Polling needs a cursor that means "everything after this point". Ordering by
 * (MSG_CREATED_AT, MSG_ID) cannot do that: MSG_CREATED_AT is a plain `datetime`
 * with no sub-second part, and MSG_ID is random, so two messages stored in the
 * same second end up ordered by chance. A message inserted after the one the app
 * already holds can sort *before* the cursor and then never be delivered.
 *
 * MSG_SEQ is an auto-increment, so it reflects true insertion order and the
 * cursor becomes exact. The client contract does not change: the app still sends
 * ?after=<MSG_ID> and the server resolves that id to its sequence.
 *
 * Written as raw SQL on purpose. The schema builder turns any auto-increment
 * column into a primary key, and `message` already has one (MSG_ID); MySQL only
 * permits a second auto-increment column when it is indexed but not primary.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Existing rows are numbered in physical order by the ALTER itself.
        DB::statement('ALTER TABLE `message`
            ADD COLUMN `MSG_SEQ` bigint unsigned NOT NULL AUTO_INCREMENT AFTER `MSG_ID`,
            ADD UNIQUE KEY `UNQ_MESSAGE_SEQ` (`MSG_SEQ`),
            DROP INDEX `IDX_MESSAGE_CONVERSATION_TIME`,
            ADD INDEX `IDX_MESSAGE_CONVERSATION_SEQ` (`CONV_ID`, `MSG_SEQ`)');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE `message`
            DROP INDEX `IDX_MESSAGE_CONVERSATION_SEQ`,
            DROP INDEX `UNQ_MESSAGE_SEQ`,
            DROP COLUMN `MSG_SEQ`,
            ADD INDEX `IDX_MESSAGE_CONVERSATION_TIME` (`CONV_ID`, `MSG_CREATED_AT`)');
    }

    public function schemaUp(): void
    {
        // No-op: this project loads its base tables from a committed SQL dump,
        // not from migrations, so there is no sqlite builder path to support.
    }
};
