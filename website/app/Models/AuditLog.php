<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * Administrator change history. Request auditing records persisted changes;
 * report_action separately retains moderation steps needed for undo.
 * Custom timestamps are set explicitly because this table has no updated column.
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
        'AUD_ACTOR_NAME',
        'AUD_TARGET_TYPE',
        'AUD_TARGET_ID',
        'AUD_ROUTE',
        'AUD_CHANGES',
    ];

    protected $casts = ['AUD_CREATED_AT' => 'datetime', 'AUD_CHANGES' => 'array'];

    /**
     * Write one audit row. Best-effort by design.
     *
     * The caller has already committed the decision the row describes, so a
     * failure here must never surface as an error to the moderator: they would
     * see a failed request for work that genuinely succeeded and be tempted to
     * do it again. The caller wraps this in its own try/catch where it matters;
     * the id is still drawn here so every caller writes the same shape.
     */
    public static function record(string $action, ?string $details, ?string $adminId, array $context = []): void
    {
        if ($adminId === null && empty($context)) {
            return;
        }

        self::create([
            'AUD_ID' => self::newId(),
            'AUD_ACTION' => Str::limit($action, 100, ''),
            'AUD_DETAILS' => $details,
            'AUD_CREATED_AT' => now(),
            'USR_ID' => $adminId,
            'AUD_ACTOR_NAME' => $context['actor_name'] ?? null,
            'AUD_TARGET_TYPE' => $context['target_type'] ?? null,
            'AUD_TARGET_ID' => $context['target_id'] ?? null,
            'AUD_ROUTE' => $context['route'] ?? null,
            'AUD_CHANGES' => $context['changes'] ?? null,
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
