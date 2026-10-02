<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One row in the app's notification inbox.
 *
 * Not Laravel's Notifiable database notification — see the migration for why
 * this is a separate, flat table. Read state is a boolean column here rather
 * than a nullable read_at, and de-duplication matches on the real
 * NOTIF_TYPE + NOTIF_REF_ID columns instead of a JSON blob.
 *
 * No $timestamps: this table predates Eloquent timestamps and carries a single
 * NOTIF_CREATED_AT, so there is no updated_at to maintain.
 */
class UserNotification extends Model
{
    protected $table = 'NOTIFICATION';

    protected $primaryKey = 'NOTIF_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $fillable = [
        'NOTIF_ID',
        'USR_ID',
        'NOTIF_TYPE',
        'NOTIF_TITLE',
        'NOTIF_BODY',
        'NOTIF_REF_ID',
        'NOTIF_IS_READ',
        'NOTIF_CREATED_AT',
    ];

    /**
     * Whether the user has opened this one.
     *
     * Cast, because MySQL hands tinyint(1) back as an int (or as "0"/"1"
     * depending on the driver), and the Flutter client parses JSON strictly —
     * a 0 arriving as a string would not decode into a bool.
     */
    protected $casts = [
        'NOTIF_IS_READ' => 'boolean',
    ];

    /**
     * The event taxonomy, shared with the service and the mobile app.
     *
     * Deliberately absent: any message/chat type. Chat has its own table and its
     * own unread badge, and a chat message must never turn up in this inbox.
     */
    public const TYPES = [
        'LISTING_EXPIRING_SOON',
        'LISTING_EXPIRED',
        'LISTING_REMOVED',
        'SELLER_DEACTIVATED',
        'ACCOUNT_SUSPENDED',
        'ACCOUNT_REACTIVATED',
        'REPORT_UPDATE',
        'HARVEST_REMINDER',
        'SETUP_COMPLETE',
    ];

    public function user()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    /**
     * A random, unused NOTIF_ID.
     *
     * Six uppercase characters, checked against the table for uniqueness —
     * the same convention every other model in this schema uses, because
     * 36^6 is small enough that a collision is plausible over time.
     */
    public static function newId(): string
    {
        do {
            $id = strtoupper(\Illuminate\Support\Str::random(6));
        } while (self::where('NOTIF_ID', $id)->exists());

        return $id;
    }
}