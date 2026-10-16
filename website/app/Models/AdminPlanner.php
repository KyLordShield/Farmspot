<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * A personal note/reminder or calendar event belonging to one admin.
 *
 * See the create_admin_planner_table migration for why both live in one table.
 * Everything here is scoped to the signed-in admin: the dashboard never reads
 * another admin's rows, and the controller refuses to touch an id that is not
 * the caller's.
 */
class AdminPlanner extends Model
{
    protected $table = 'admin_planner';

    protected $primaryKey = 'APL_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    // The table has APL_CREATED_AT / APL_UPDATED_AT, not the names Eloquent
    // expects, and both are written by hand.
    public $timestamps = false;

    public const TYPE_NOTE = 'NOTE';

    public const TYPE_EVENT = 'EVENT';

    protected $fillable = [
        'APL_ID',
        'USR_ID',
        'APL_TYPE',
        'APL_TITLE',
        'APL_BODY',
        'APL_DATETIME',
        'APL_IS_DONE',
        'APL_CREATED_AT',
        'APL_UPDATED_AT',
    ];

    protected $casts = [
        'APL_IS_DONE' => 'boolean',
        'APL_DATETIME' => 'datetime',
        'APL_CREATED_AT' => 'datetime',
        'APL_UPDATED_AT' => 'datetime',
    ];

    /**
     * Rows belonging to one admin.
     */
    public function scopeForUser(Builder $query, string $userId): Builder
    {
        return $query->where('USR_ID', $userId);
    }

    public function isOverdue(): bool
    {
        return ! $this->APL_IS_DONE
            && $this->APL_DATETIME !== null
            && $this->APL_DATETIME->isPast();
    }

    /**
     * A six-character uppercase id, in the same shape as the rest of the schema.
     */
    public static function newId(): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (self::where('APL_ID', $id)->exists());

        return $id;
    }
}
