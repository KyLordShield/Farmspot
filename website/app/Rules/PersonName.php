<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Http\Request;

class PersonName implements ValidationRule
{
    public const MAX_LENGTH = 150;

    public static function normalize(Request $request, string $field): void
    {
        $value = $request->input($field);

        if (is_string($value)) {
            $normalized = preg_replace('/[\p{Z}\t\r\n]+/u', ' ', $value);
            $request->merge([$field => trim($normalized ?? $value, ' ')]);
        }
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! preg_match("/\\A(?=.*\\p{L})[\\p{L}\\p{M} .'\\x{2019}\\p{Pd}]+\\z/u", $value)) {
            $fail('Enter a name using letters, spaces, periods, apostrophes, or hyphens.');
        }
    }
}
