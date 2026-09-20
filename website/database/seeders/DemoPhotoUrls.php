<?php

namespace Database\Seeders;

/**
 * Resolves the committed demo crop/farm photo URLs (stored on Cloudinary)
 * from database/seeders/demo_photo_urls.json.
 */
final class DemoPhotoUrls
{
    private static ?array $data = null;

    public static function crop(string $slug, string $file): string
    {
        return self::data()['crops'][$slug][$file] ?? '';
    }

    public static function farm(string $farm, string $file): string
    {
        return self::data()['farms'][$farm][$file] ?? '';
    }

    private static function data(): array
    {
        if (self::$data === null) {
            self::$data = json_decode(
                (string) file_get_contents(__DIR__ . '/demo_photo_urls.json'),
                true
            ) ?? [];
        }

        return self::$data;
    }
}