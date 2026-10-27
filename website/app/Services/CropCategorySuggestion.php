<?php

namespace App\Services;

use App\Models\CropCategory;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CropCategorySuggestion
{
    public static function normalize(string $name): string
    {
        $words = preg_split('/[^a-z0-9]+/', Str::lower(Str::ascii($name)), -1, PREG_SPLIT_NO_EMPTY);

        return implode(' ', array_map(fn ($word) => Str::singular($word), $words));
    }

    public function suggest(?string $crop): ?string
    {
        $key = self::normalize($crop ?? '');
        if ($key === '') {
            return null;
        }
        $matches = [];
        foreach (config('crop_categories') as $id => $category) {
            foreach ($category['crops'] as $alias) {
                // Whole phrases only: "apple" does not match "pineapple".
                if (str_contains(' '.$key.' ', ' '.self::normalize($alias).' ')) {
                    $matches[$id] = true;
                    break;
                }
            }
        }

        // Mixed-category titles need a seller's choice, not an arbitrary winner.
        return count($matches) === 1 ? array_key_first($matches) : null;
    }

    public function assign(?string $crop): string
    {
        $id = $this->suggest($crop) ?? 'OTHERS';
        if (! CropCategory::whereKey($id)->exists()) {
            throw ValidationException::withMessages(['category_id' => 'Please choose an available crop category.']);
        }

        return $id;
    }

    public function aliases(string $categoryId): array
    {
        $aliases = config("crop_categories.{$categoryId}.crops", []);

        // Ship singular and plural spellings too, so the phone can match locally
        // without adding an API call for every keystroke.
        return array_values(array_unique([...$aliases, ...array_map(fn ($alias) => Str::plural($alias), $aliases), ...array_map(fn ($alias) => Str::singular($alias), $aliases)]));
    }
}
