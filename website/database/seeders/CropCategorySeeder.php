<?php

namespace Database\Seeders;

use App\Models\CropCategory;
use Illuminate\Database\Seeder;

/**
 * Real Philippine-vegetable-farming crop categories for the pilot. The
 * pre-existing "Vegetables" row (CAT_ID TSTCAT) is test data that existing
 * listings reference, so it is deliberately left untouched — these are added
 * alongside it. CAT_ICON values match the Material icon names the Flutter
 * category grid understands (spa, local_florist, agriculture, grain, grass).
 */
class CropCategorySeeder extends Seeder
{
    public function run(): void
    {
        $categories = [
            [
                'CAT_ID' => 'LEAFVG',
                'CAT_NAME' => 'Leafy Vegetables',
                'CAT_ICON' => 'spa',
                'CAT_DESCRIPTION' => 'Leaf and stem crops harvested fresh: cabbage, pechay, lettuce, kangkong, mustasa.',
            ],
            [
                'CAT_ID' => 'FRTVEG',
                'CAT_NAME' => 'Fruit Vegetables',
                'CAT_ICON' => 'local_florist',
                'CAT_DESCRIPTION' => 'Crops grown for their edible fruit: tomato, eggplant, okra, squash, cucumber, ampalaya.',
            ],
            [
                'CAT_ID' => 'ROOTCP',
                'CAT_NAME' => 'Root Crops',
                'CAT_ICON' => 'agriculture',
                'CAT_DESCRIPTION' => 'Underground root and tuber crops: carrot, radish, sweet potato, cassava, ube.',
            ],
            [
                'CAT_ID' => 'LEGMES',
                'CAT_NAME' => 'Legumes',
                'CAT_ICON' => 'grain',
                'CAT_DESCRIPTION' => 'Pod and seed crops: string beans, pole sitao, munggo, peanuts.',
            ],
            [
                'CAT_ID' => 'HRBSPC',
                'CAT_NAME' => 'Herbs & Spices',
                'CAT_ICON' => 'grass',
                'CAT_DESCRIPTION' => 'Aromatic herbs and flavoring crops: garlic, onion, ginger, chili, basil, lemongrass.',
            ],
        ];

        foreach ($categories as $category) {
            CropCategory::updateOrCreate(
                ['CAT_ID' => $category['CAT_ID']],
                $category,
            );
        }
    }
}
