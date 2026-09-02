<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Farmer extends Model
{
    protected $table = 'farmer';

    protected $primaryKey = 'FMR_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function buyer()
    {
        return $this->belongsTo(Buyer::class, 'BUY_ID', 'BUY_ID');
    }

    public function farms()
    {
        return $this->hasMany(Farm::class, 'FMR_ID', 'FMR_ID');
    }
}