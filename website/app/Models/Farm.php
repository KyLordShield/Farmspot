<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Farm extends Model
{
    protected $table = 'farm';

    protected $primaryKey = 'FRM_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function farmer()
    {
        return $this->belongsTo(Farmer::class, 'FMR_ID', 'FMR_ID');
    }

    public function photos()
    {
        return $this->hasMany(FarmPhoto::class, 'FRM_ID', 'FRM_ID');
    }
}