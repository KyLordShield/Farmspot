<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CropCategory extends Model
{
    protected $table = 'crop_category';

    protected $primaryKey = 'CAT_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    /**
     * The icons the app can actually draw, mapped to what they mean.
     *
     * This list is not a preference — it is the vocabulary. The app maps CAT_ICON
     * through a switch in add_crop_screen.dart (_iconForCategory) and anything it
     * does not recognise falls through to a guess based on the category NAME.
     * That fallback is why a typo used to be silent: an admin typing "spaa" got no
     * error, and a generic leaf instead of the flower they had picked.
     *
     * So the names live here, the admin panel renders all eight as clickable
     * pictures, and validation rejects anything else. Nobody has to memorise a
     * Material icon name, and a wrong value fails loudly rather than quietly.
     *
     * The glyphs are Material Icons, loaded from the Google Fonts stylesheet by
     * the panel, so an admin sees exactly the icon the app will render rather
     * than an approximation in a different set.
     *
     * Adding an icon here without adding the matching case in the app is the one
     * way to break this: the value would validate, and the app would still fall
     * back. The Flutter switch is the other half of this list.
     */
    public const ICONS = [
        'eco' => 'General / mixed produce',
        'spa' => 'Leafy vegetables',
        'grass' => 'Herbs and grasses',
        'grain' => 'Grains and cereals',
        'local_florist' => 'Fruit vegetables',
        'agriculture' => 'Farming in general',
        'water_drop' => 'Wet crops, aquaculture',
        'pets' => 'Livestock and poultry',
    ];

    public function listings()
    {
        return $this->hasMany(Listing::class, 'CAT_ID', 'CAT_ID');
    }

    public function insights()
    {
        return $this->hasMany(Insight::class, 'CAT_ID', 'CAT_ID');
    }

    public function trends()
    {
        return $this->hasMany(Trend::class, 'CAT_ID', 'CAT_ID');
    }

    /**
     * How many rows anywhere still point at this category.
     *
     * NOT just listings. Three tables carry a CAT_ID foreign key into
     * crop_category — listing, insight and trend — and none of them were
     * declared ON DELETE CASCADE. So a category with no listings but a month of
     * recorded trends cannot be deleted either, and a delete guard that only
     * counted listings would let that through to the database, which answers
     * with a raw SQLSTATE 23000 rather than an explanation.
     *
     * insight and trend are analytics rows, so they are the reason a category
     * that looks unused in the panel can still be genuinely undeletable. The
     * panel counts all three and the delete guard refuses on any of them.
     *
     * The keyed form is what the admin panel and the guard both read, so the
     * button that is disabled and the refusal it stands in for cannot disagree.
     */
    public function usageCounts(): array
    {
        return [
            'listings' => $this->listings()->count(),
            'insights' => $this->insights()->count(),
            'trends' => $this->trends()->count(),
        ];
    }
}