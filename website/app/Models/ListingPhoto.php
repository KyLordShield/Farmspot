<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ListingPhoto extends Model
{
    protected $table = 'listing_photo';

    protected $primaryKey = 'LPHOTO_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function listing()
    {
        return $this->belongsTo(Listing::class, 'LST_ID', 'LST_ID');
    }
}
