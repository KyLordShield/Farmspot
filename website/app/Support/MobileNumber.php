<?php

namespace App\Support;

class MobileNumber
{
    public const PATTERN = 'regex:/^09[0-9]{9}$/';

    public const REQUIRED = 'Please enter your mobile number.';

    public const INVALID = 'Please enter an 11-digit number starting with 09 (e.g. 09171234567).';

    public const DUPLICATE = 'That mobile number is already registered.';

    public static function messages(string $field): array
    {
        return [
            "{$field}.required" => self::REQUIRED,
            "{$field}.string" => self::INVALID,
            "{$field}.regex" => self::INVALID,
            "{$field}.unique" => self::DUPLICATE,
        ];
    }
}
