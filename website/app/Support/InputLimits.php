<?php

namespace App\Support;

class InputLimits
{
    public const CROP_NAME = 40;

    public const FARM_NAME = 100;

    public const DESCRIPTION = 1000;

    public const BARANGAY = 100;

    public const ADDRESS = 255;

    public static function messages(): array
    {
        return [
            'crop_icon.max' => 'Crop name must be :max characters or fewer.',
            'name.max' => 'Farm name must be :max characters or fewer.',
            'description.max' => 'Description must be :max characters or fewer.',
            'barangay.max' => 'Barangay must be :max characters or fewer.',
        ];
    }
}
