<?php

namespace App\Support;

/**
 * Mirrors mobile DocumentTextCheck name matching so submitted OCR text
 * can be verified server-side against the authenticated seller's name.
 */
final class DocumentNameMatcher
{
    public static function normalize(string $text): string
    {
        $upper = mb_strtoupper($text, 'UTF-8');
        $upper = str_replace(['Ñ', 'É'], ['N', 'E'], $upper);
        $clean = preg_replace('/[^A-Z0-9]+/', ' ', $upper) ?? '';

        return trim($clean);
    }

    public static function matches(string $name, string $text): bool
    {
        $parts = array_values(array_filter(
            explode(' ', self::normalize($name)),
            static fn (string $p): bool => $p !== ''
        ));
        $significant = array_values(array_filter(
            $parts,
            static fn (string $p): bool => strlen($p) > 1
        ));

        if (count($significant) < 2) {
            return false;
        }

        $words = array_flip(array_filter(
            explode(' ', self::normalize($text)),
            static fn (string $w): bool => $w !== ''
        ));

        foreach ($significant as $token) {
            if (! isset($words[$token])) {
                return false;
            }
        }

        return true;
    }
}
