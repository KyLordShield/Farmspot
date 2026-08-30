<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Whitelist extends Model
{
    protected $table = 'whitelist';

    protected $primaryKey = 'WLST_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function addedBy()
    {
        return $this->belongsTo(User::class, 'USR_ADDED_ID', 'USR_ID');
    }

    public function deactivatedBy()
    {
        return $this->belongsTo(User::class, 'USR_DEACTIVATED_ID', 'USR_ID');
    }
}