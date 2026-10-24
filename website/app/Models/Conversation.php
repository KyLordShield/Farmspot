<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Conversation extends Model
{
    protected $table = 'conversation';

    protected $primaryKey = 'CONV_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function buyRequest()
    {
        return $this->belongsTo(BuyRequest::class, 'BRQ_ID', 'BRQ_ID');
    }

    public function farm()
    {
        return $this->belongsTo(Farm::class, 'FRM_ID', 'FRM_ID');
    }

    public function listing()
    {
        return $this->belongsTo(Listing::class, 'LST_ID', 'LST_ID');
    }

    public function messages()
    {
        return $this->hasMany(Message::class, 'CONV_ID', 'CONV_ID');
    }

    public function farmer()
    {
        return $this->belongsTo(Farmer::class, 'FMR_ID', 'FMR_ID');
    }
}
