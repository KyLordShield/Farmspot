<?php

namespace App\Models;

use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    /**
     * The table associated with the model.
     */
    protected $table = 'user';

    /**
     * The primary key associated with the table.
     */
    protected $primaryKey = 'USR_ID';

    /**
     * Indicates if the IDs are auto-incrementing.
     * Your USR_ID is a random 6-char string, not an auto-increment number.
     */
    public $incrementing = false;

    /**
     * The data type of the primary key.
     */
    protected $keyType = 'string';

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'USR_ID',
        'USR_NAME',
        'USR_EMAIL',
        'USR_PASSWORD',
        'USR_MOBILE_NUMBER',
        'USR_ADDRESS',
        'USR_PHOTO_PATH',
        'USR_ROLE',
        'USR_IS_SELLER',
        'USR_STATUS',
        // Set when an admin deactivates the account through the report queue or
        // the appeals panel. USR_TAKEDOWN_REASON is what the app shows the owner
        // and the marker that separates an admin takedown (appealable) from an
        // account switched off without a reason (not appealable). The other two
        // remember when it happened and which listings the takedown itself hid,
        // so restoring the account brings back only what we removed.
        'USR_TAKEDOWN_REASON',
        'USR_TAKEDOWN_AT',
        'USR_HIDDEN_BY_TAKEDOWN',
        'USR_CREATED_AT',
    ];

    /**
     * The attributes that should be hidden for serialization.
     */
    protected $hidden = [
        'USR_PASSWORD',
    ];

    /**
     * Tell Laravel which column holds the password,
     * since it's not called "password" here.
     */
    public function getAuthPassword()
    {
        return $this->USR_PASSWORD;
    }

    /**
     * Tell Laravel's mail channel where to deliver notifications.
     *
     * Without this the channel falls back to `$this->email`, which is null on
     * this schema - the address lives in USR_EMAIL. The failure is silent: the
     * message is built and handed to the mailer with no recipient, so nothing
     * is sent and nothing is logged, while the caller still sees success.
     * That is how the app's password-reset email could be configured correctly
     * and still never arrive.
     *
     * Fixed here rather than per-notification so every mail notification for
     * this model is covered, including any added later.
     *
     * Takes the optional $notification argument because the framework's
     * routeNotificationFor() calls this method as
     * `$this->{$method}($notification)`.
     */
    public function routeNotificationForMail($notification = null): string
    {
        return (string) $this->USR_EMAIL;
    }

    public function buyer()
    {
        return $this->hasOne(Buyer::class, 'USR_ID', 'USR_ID');
    }

    /**
     * Laravel normally expects created_at/updated_at columns.
     * You only have USR_CREATED_AT and no "updated at" column,
     * so we turn off automatic timestamp handling.
     */
    public $timestamps = false;

    /**
     * Deactivated by an admin with a reason the owner can see and contest.
     *
     * Narrower than a plain USR_STATUS check on purpose. An account can be
     * DEACTIVATED with no reason at all — an old suspension, a manual toggle in
     * the users panel before reasons existed — and there is nothing meaningful
     * to appeal against in that case. Only a reason makes it a takedown with a
     * case to answer, which is the same distinction the mobile login uses to
     * decide between the appeal screen and "contact the Association".
     */
    public function isTakenDown(): bool
    {
        return $this->USR_STATUS === 'DEACTIVATED' && $this->USR_TAKEDOWN_REASON !== null;
    }

    /**
     * Whether this account is a farmer/seller.
     *
     * USR_ROLE is only GENERAL_USER or ADMIN — there is no FARMER value, so a
     * screen that compares USR_ROLE against 'FARMER' can never match. The real
     * marker is USR_IS_SELLER, which admin approval sets when a seller request
     * goes through and SellerController clears when seller mode is switched
     * off. Reading it here keeps every admin screen agreeing on who is a
     * farmer.
     */
    public function isFarmer(): bool
    {
        return (int) $this->USR_IS_SELLER === 1;
    }
}