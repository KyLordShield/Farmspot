<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Listing extends Model
{
    protected $table = 'listing';

    protected $primaryKey = 'LST_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function farmer()
    {
        return $this->belongsTo(Farmer::class, 'FMR_ID', 'FMR_ID');
    }

    public function farm()
    {
        return $this->belongsTo(Farm::class, 'FRM_ID', 'FRM_ID');
    }

    public function category()
    {
        return $this->belongsTo(CropCategory::class, 'CAT_ID', 'CAT_ID');
    }

    /**
     * Full photo gallery, oldest-first so "the oldest remaining photo" is a
     * deterministic fallback when the primary is deleted. LST_IMAGE remains a
     * denormalized cache of whichever row has LPHOTO_IS_PRIMARY = 1.
     */
    public function photos()
    {
        return $this->hasMany(ListingPhoto::class, 'LST_ID', 'LST_ID')
            ->orderBy('LPHOTO_UPLOADED_AT')
            ->orderBy('LPHOTO_ID');
    }

    public function primaryPhoto()
    {
        return $this->hasOne(ListingPhoto::class, 'LST_ID', 'LST_ID')
            ->where('LPHOTO_IS_PRIMARY', 1);
    }
}