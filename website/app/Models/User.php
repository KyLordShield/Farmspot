<?php

namespace App\Models;

use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use HasFactory, Notifiable;

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
        'USR_ROLE',
        'USR_IS_SELLER',
        'USR_STATUS',
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
     * Laravel normally expects created_at/updated_at columns.
     * You only have USR_CREATED_AT and no "updated at" column,
     * so we turn off automatic timestamp handling.
     */
    public $timestamps = false;
}