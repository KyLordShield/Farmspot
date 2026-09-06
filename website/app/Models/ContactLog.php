<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ContactLog extends Model
{
    protected $table = 'contact_log';

    protected $primaryKey = 'CTL_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function user()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    public function listing()
    {
        return $this->belongsTo(Listing::class, 'LST_ID', 'LST_ID');
    }
}