<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BuyRequest extends Model
{
    protected $table = 'buy_request';

    protected $primaryKey = 'BRQ_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function owner()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    public function conversations()
    {
        return $this->hasMany(Conversation::class, 'BRQ_ID', 'BRQ_ID');
    }
}
