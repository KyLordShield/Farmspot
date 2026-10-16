<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * Append-only record of who did something and when.
 *
 * Nothing wrote to this table while the report queue's decisions lived in
 * ReportAction / report_action, which keeps one row per step, records the
 * previous value so undo is exact, and orders by insertion. That trail is
 * still the right one for a moderator clicking a button on a report.
 *
 * Re-evaluations are different. Approving or denying an appeal is a decision
 * about a person that has no undo button and must be answerable afterwards —
 * "who restored this account, when, and on what grounds" — so those two
 * outcomes are written here as a small, permanent audit row alongside the
 * ReviewRequest the decision is recorded on.
 *
 * The table has AUD_CREATED_AT and no AUD_UPDATED_AT, so Eloquent's default
 * timestamps would try to write a column that does not exist; they are off and
 * the timestamp is set by hand. Fillable is spelled out rather than switching
 * to $guarded = [] because this is an audit trail: what an application may
 * write into it is worth keeping explicit.
 */
class AuditLog extends Model
{
    protected $table = 'audit_log';

    protected $primaryKey = 'AUD_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $fillable = [
        'AUD_ID',
        'AUD_ACTION',
        'AUD_DETAILS',
        'AUD_CREATED_AT',
        'USR_ID',
    ];

    /**
     * Write one audit row. Best-effort by design.
     *
     * The caller has already committed the decision the row describes, so a
     * failure here must never surface as an error to the moderator: they would
     * see a failed request for work that genuinely succeeded and be tempted to
     * do it again. The caller wraps this in its own try/catch where it matters;
     * the id is still drawn here so every caller writes the same shape.
     */
    public static function record(string $action, ?string $details, ?string $adminId): void
    {
        if ($adminId === null) {
            return;
        }

        self::create([
            'AUD_ID' => self::newId(),
            'AUD_ACTION' => Str::limit($action, 100, ''),
            'AUD_DETAILS' => $details,
            'AUD_CREATED_AT' => now(),
            'USR_ID' => $adminId,
        ]);
    }

    private static function newId(): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (self::where('AUD_ID', $id)->exists());

        return $id;
    }
}
