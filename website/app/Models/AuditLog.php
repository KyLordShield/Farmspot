<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Append-only record of who did something and when.
 *
 * Nothing writes to this table. Report enforcement used to record its decisions
 * here, one row per action, but that capped each report at a single action and
 * made undo ambiguous when two were applied in the same second. The trail for
 * reports now lives in ReportAction / report_action, which keeps one row per
 * step, records the previous value so undo is exact, and orders by insertion.
 *
 * The table is still in the schema, so this is left as a plain model rather than
 * deleted. If it is ever used again it needs `public $timestamps = false;` and
 * `$table = 'audit_log'`: the table has AUD_CREATED_AT and no AUD_UPDATED_AT, so
 * Eloquent's default handling would try to write a column that does not exist.
 */
class AuditLog extends Model
{
}
