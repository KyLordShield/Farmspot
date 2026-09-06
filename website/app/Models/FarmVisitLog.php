<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FarmVisitLog extends Model
{
    protected $table = 'farm_visit_log';

    protected $primaryKey = 'FVL_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function user()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    public function farm()
    {
        return $this->belongsTo(Farm::class, 'FRM_ID', 'FRM_ID');
    }
}