<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Give RPT_ID the same 6-character shape as every other id in this schema.
 *
 * RPT_ID was int(11) AUTO_INCREMENT, the only numeric id in a database where
 * LST_ID, MSG_ID, FMR_ID, USR_ID and BUY_ID are all char(6). That inconsistency
 * was not cosmetic: the API returned the report id as a JSON *number* while
 * every other id in the same payloads was a string, and the app crashed on
 * `as String` with "type 'int' is not a subtype of type 'String'" — after the
 * report had already been saved, so the buyer was shown a failure for a report
 * that was sitting in the moderator's queue.
 *
 * Random 6 digits rather than a sequence, because a report id should not be
 * enumerable by a buyer who wants to walk the complaint queue: 100000-999999
 * instead of 1, 2, 3. Six digits is a 900k keyspace against a table that will
 * hold thousands of rows, and the collision check below makes a clash
 * impossible.
 */
return new class extends Migration
{
    public function up(): void
    {
        // The primary key has to come off before the column can change type,
        // because AUTO_INCREMENT is carried by the key. MySQL refuses to drop
        // a key while the column it carries is still AUTO_INCREMENT (error
        // 1075), so the auto attribute is removed in the same ALTER that drops
        // the key rather than in a statement of its own.
        DB::statement('ALTER TABLE report MODIFY RPT_ID int(11) NOT NULL');
        DB::statement('ALTER TABLE report DROP PRIMARY KEY');
        DB::statement('ALTER TABLE report MODIFY RPT_ID char(6) NOT NULL');

        // Snapshot the old ids first. Re-reading the table inside the loop
        // would see the rows already rewritten.
        $old = DB::table('report')->pluck('RPT_ID')->all();

        $taken = [];
        foreach ($old as $from) {
            do {
                $next = (string) random_int(100000, 999999);
            } while (in_array($next, $taken, true) || DB::table('report')->where('RPT_ID', $next)->exists());

            $taken[] = $next;
            DB::table('report')->where('RPT_ID', $from)->update(['RPT_ID' => $next]);
        }

        DB::statement('ALTER TABLE report ADD PRIMARY KEY (RPT_ID)');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE report MODIFY RPT_ID char(6) NOT NULL');
        DB::statement('ALTER TABLE report DROP PRIMARY KEY');
        DB::statement('ALTER TABLE report MODIFY RPT_ID int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY');
    }
};
