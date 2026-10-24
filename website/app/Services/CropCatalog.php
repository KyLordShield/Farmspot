<?php

namespace App\Services;

use App\Models\Listing;
use Illuminate\Support\Str;

class CropCatalog
{
    private function normalize(string $name): string
    {
        return preg_replace('/[^a-z0-9]/', '', strtolower(Str::ascii(trim($name))));
    }

    public function all(): array
    {
        $catalog = config('buy_request_crops');
        $catalog['Hyacinth Beans'] = ['bataw'];
        $catalog['Chayote'] = ['sayote'];
        $catalog['Green Beans'] = ['baguio beans'];
        $catalog['Beans'] = [];
        $catalog['Chili Pepper'] = array_merge($catalog['Chili Pepper'], ['sili spada', 'chili']);
        // Keep real listings outside the starter catalog discoverable too.
        $known = [];
        foreach ($catalog as $name => $aliases) {
            foreach ([$name, ...$aliases] as $alias) {
                $known[$this->normalize($alias)] = $name;
            }
        }
        foreach (Listing::with('category')->where('LST_AVAILABILITY', 'ACTIVE')->whereIn('LST_STATUS', ['AVAILABLE_NOW', 'SOON_TO_HARVEST'])->whereHas('farm', fn ($q) => $q->where('FRM_STATUS', 'APPROVED')->where('FRM_PIN_ACTIVE', 1)->whereHas('farmer.buyer.user', fn ($u) => $u->where('USR_STATUS', 'ACTIVE')->where('USR_IS_SELLER', 1)))->get() as $listing) {
            $name = trim((string) ($listing->LST_CROP_ICON ?: $listing->category?->CAT_NAME));
            if ($name !== '' && ! isset($known[$this->normalize($name)])) {
                $catalog[$name] = [];
                $known[$this->normalize($name)] = $name;
            }
        }
        ksort($catalog, SORT_NATURAL | SORT_FLAG_CASE);

        return $catalog;

    }

    public function key(string $name): string
    {
        $key = $this->normalize($name);
        // Canonical aliases do not depend on current stock.
        $catalog = config('buy_request_crops');
        $catalog['Hyacinth Beans'] = ['bataw'];
        $catalog['Chayote'] = ['sayote'];
        $catalog['Green Beans'] = ['baguio beans'];
        $catalog['Chili Pepper'] = [...$catalog['Chili Pepper'], 'sili spada', 'chili'];
        foreach ($catalog as $crop => $aliases) {
            foreach ([$crop, ...$aliases] as $alias) {
                if ($this->normalize($alias) === $key) {
                    return $this->normalize($crop);
                }
            }
        }

        return $key;
    }
}
