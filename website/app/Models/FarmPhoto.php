<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FarmPhoto extends Model
{
    protected $table = 'farm_photo';

    protected $primaryKey = 'FPHOTO_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function farm()
    {
        return $this->belongsTo(Farm::class, 'FRM_ID', 'FRM_ID');
    }
}
