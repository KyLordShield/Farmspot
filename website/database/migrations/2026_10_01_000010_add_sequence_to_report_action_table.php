<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A per-table insertion counter, so "the most recent action" is a fact rather
 * than a guess.
 *
 * Undo reads the newest action still in force. That was ordered by
 * RAC_APPLIED_AT, which depends on the clock: two actions applied on one report
 * in the same second were indistinguishable, and undo then popped whichever row
 * the database happened to return first. In practice that meant taking a listing
 * down and deactivating its seller, clicking undo once, and getting back a
 * listing that was on sale again while the seller stayed deactivated.
 *
 * Microsecond timestamps (see the previous migration) make that collision very
 * unlikely, but "very unlikely" is the wrong property for a button whose whole
 * job is to put things back the way they were. RAC_SEQ is assigned by the
 * database in insertion order, so it cannot tie and does not depend on two
 * requests agreeing about the time.
 *
 * RAC_ID stays the primary key — it is the six-character id the rest of this
 * schema uses, and the app never sees this column.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Raw DDL rather than the schema builder: Blueprint::autoIncrement()
        // also implies a primary key, and RAC_ID is already the primary key, so
        // the builder emits "Multiple primary key defined" (error 1068). MySQL
        // only requires that the single AUTO_INCREMENT column be *a* key, so an
        // ordinary index is enough and is what this asks for.
        DB::statement(
            'ALTER TABLE report_action
                ADD COLUMN RAC_SEQ bigint unsigned NOT NULL AUTO_INCREMENT AFTER RAC_ID,
                ADD INDEX IDX_ACTION_SEQ (RAC_SEQ)'
        );
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE report_action DROP INDEX IDX_ACTION_SEQ, DROP COLUMN RAC_SEQ');
    }
};
