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

    /**
     * Every time a buyer taps call or SMS on this listing.
     *
     * There is no view counter or rating in the schema, so this is the honest
     * popularity signal: a buyer who contacted the seller is a stronger signal
     * than one who merely scrolled past. Counted, not read, by the "popular"
     * sort on the public feed.
     */
    public function contacts()
    {
        return $this->hasMany(ContactLog::class, 'LST_ID', 'LST_ID');
    }

    public function primaryPhoto()
    {
        return $this->hasOne(ListingPhoto::class, 'LST_ID', 'LST_ID')
            ->where('LPHOTO_IS_PRIMARY', 1);
    }

    /**
     * LST_AVAILABILITY = 'REMOVED' is a moderation verdict, not a seller state.
     * Once set — by an admin in the web panel, or by a report taken down — the
     * listing leaves the buyer feed and the seller's My Farm, and no seller-side
     * action may bring it back. Note this is NOT the same as LST_STATUS:
     * NOT_AVAILABLE is a farmer saying "this crop is gone", which is still
     * shown on the public farm profile; REMOVED is us saying it cannot be
     * edited, so it must not be.
     */
    public const AVAILABILITY_REMOVED = 'REMOVED';

    /**
     * The one piece of copy for every endpoint that refuses to act on a removed
     * listing. Kept here rather than repeated per controller so the farmer sees
     * the same sentence whichever route they hit, and cannot end up with two
     * different explanations for the same state.
     */
    public const REMOVED_EDIT_MESSAGE =
        'This listing was removed and can no longer be edited.';

    public function isRemoved(): bool
    {
        return $this->LST_AVAILABILITY === self::AVAILABILITY_REMOVED;
    }
}