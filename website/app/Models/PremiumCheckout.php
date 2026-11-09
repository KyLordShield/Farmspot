<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PremiumCheckout extends Model
{
    protected $table = 'premium_checkout';

    protected $primaryKey = 'ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    protected $casts = ['CREATE_PAYLOAD' => 'array', 'AMOUNT' => 'integer', 'PAID_AT' => 'datetime', 'PREMIUM_UNTIL' => 'datetime', 'CREATED_AT' => 'datetime'];
}
