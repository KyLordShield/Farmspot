<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One enforcement step a moderator applied to a report.
 *
 * Append-only. An action that is undone is marked with RAC_REVERTED_AT rather
 * than deleted, because "who removed this, when, and did anyone put it back"
 * is exactly the question an audit is for — and because a moderator who undoes
 * the wrong thing needs to be able to see that it happened.
 */
class ReportAction extends Model
{
    protected $table = 'report_action';

    protected $primaryKey = 'RAC_ID';

    protected $keyType = 'string';

    public $incrementing = false;

    public $timestamps = false;

    /**
     * Write datetimes with microseconds.
     *
     * Eloquent serialises date attributes through getDateFormat(), which
     * defaults to 'Y-m-d H:i:s' and silently drops the sub-second part. The
     * column is datetime(6) precisely so that two actions applied on the same
     * report in the same second stay distinguishable — undo pops the newest one
     * still in force, and with the fraction truncated both rows carry an
     * identical timestamp and MySQL has no tiebreaker to order them by.
     */
    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected $fillable = [
        'RAC_ID',
        'RPT_ID',
        'RAC_ACTION',
        'RAC_SUBJECT_TYPE',
        'RAC_SUBJECT_ID',
        'RAC_PREV',
        'RAC_NOTE',
        'RAC_BY',
        'RAC_APPLIED_AT',
        'RAC_REVERTED_AT',
        'RAC_REVERTED_BY',
    ];

    public function report()
    {
        return $this->belongsTo(Report::class, 'RPT_ID', 'RPT_ID');
    }

    /**
     * The admin who applied it.
     */
    public function moderator()
    {
        return $this->belongsTo(User::class, 'RAC_BY', 'USR_ID');
    }

    public function revertedBy()
    {
        return $this->belongsTo(User::class, 'RAC_REVERTED_BY', 'USR_ID');
    }

    public function isLive(): bool
    {
        return $this->RAC_REVERTED_AT === null;
    }

    public function label(): string
    {
        return Report::ACTION_LABELS[$this->RAC_ACTION] ?? $this->RAC_ACTION;
    }

    /**
     * What this action put back, decoded.
     *
     * Shape depends on the action: a flat ['field' => 'value'] for a single
     * column, or ['listings' => [...]] when a step touched a whole catalogue.
     */
    public function previous(): array
    {
        return $this->RAC_PREV ? (json_decode($this->RAC_PREV, true) ?: []) : [];
    }
}
