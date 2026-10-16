<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * A request to look again at a listing or an account that was taken down.
 *
 * This is the "I was reported and taken down but I did nothing wrong" path. It
 * is keyed to the TAKEDOWN, not to any single report: an admin can take
 * something down without a report ever being filed, and that owner is just as
 * entitled to contest it. That is also why a plain deactivation with no reason
 * produces no appealable row — there is no takedown to point at.
 *
 * One open request per target. A DENIED request is final until a NEW takedown
 * happens; the check for that compares the request's decision time against the
 * target's *_TAKEDOWN_AT, so a second takedown re-opens the right to appeal
 * while a repeat attempt against the same takedown is refused.
 */
class ReviewRequest extends Model
{
    protected $table = 'review_request';

    protected $primaryKey = 'RRQ_ID';

    /**
     * A 6-character id the model assigns, not the database.
     *
     * Checked against the table before it is handed back, because RRQ_ID is the
     * primary key: two rows colliding would be a 1062 error on insert rather
     * than a quiet overwrite, and the caller would see a 500 for what is just
     * bad luck on a random draw. Same shape as ReportAction::newId().
     */
    public $incrementing = false;

    protected $keyType = 'string';

    /**
     * The table has RRQ_CREATED_AT and no RRQ_UPDATED_AT, so Eloquent's
     * created_at/updated_at handling would try to write a column that does not
     * exist. Both timestamps are set by hand, like every other legacy table.
     */
    public $timestamps = false;

    public const TARGET_LISTING = 'LISTING';

    public const TARGET_USER = 'USER';

    public const STATUS_PENDING = 'PENDING';

    public const STATUS_APPROVED = 'APPROVED';

    public const STATUS_DENIED = 'DENIED';

    protected $fillable = [
        'RRQ_ID',
        'USR_ID',
        'RRQ_TARGET_TYPE',
        'RRQ_TARGET_ID',
        'RRQ_REASON',
        'RRQ_ADMIN_NOTE',
        'RRQ_STATUS',
        'RRQ_DECIDED_BY',
        'RRQ_CREATED_AT',
        'RRQ_DECIDED_AT',
    ];

    public static function newId(): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (self::where('RRQ_ID', $id)->exists());

        return $id;
    }

    /**
     * The person who filed the appeal. Always the owner of the target: a listing
     * appeal is filed from the app while signed in, and an account appeal is
     * filed after login was refused, which is why that endpoint re-checks the
     * owner's email and password before writing a row here.
     */
    public function user()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    public function decidedBy()
    {
        return $this->belongsTo(User::class, 'RRQ_DECIDED_BY', 'USR_ID');
    }

    /**
     * The listing under review, when this is a LISTING request.
     */
    public function listing()
    {
        return $this->belongsTo(Listing::class, 'RRQ_TARGET_ID', 'LST_ID');
    }

    /**
     * The account under review, when this is a USER request.
     */
    public function account()
    {
        return $this->belongsTo(User::class, 'RRQ_TARGET_ID', 'USR_ID');
    }

    public function isPending(): bool
    {
        return $this->RRQ_STATUS === self::STATUS_PENDING;
    }

    /**
     * The most recent request for a target, whatever its state.
     *
     * Used to decide whether a new appeal is allowed: a PENDING one blocks a
     * second, and a DENIED one blocks until the target is taken down again.
     */
    public static function latestFor(string $targetType, string $targetId): ?self
    {
        return self::where('RRQ_TARGET_TYPE', $targetType)
            ->where('RRQ_TARGET_ID', $targetId)
            ->orderByDesc('RRQ_CREATED_AT')
            ->orderByDesc('RRQ_ID')
            ->first();
    }
}
