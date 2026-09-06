<?php

namespace App\Support;

use Illuminate\Support\Facades\Storage;

/**
 * Deletes Cloudinary image assets the way this project uploads them: through
 * the "cloudinary" Flysystem disk, whose delete() resolves the public_id from
 * the same path used at upload time (dirname/filename, resource_type "image").
 *
 * Farm/listing rows only persist the delivered URL, never the upload path, so
 * here the storage path is reconstructed from the URL by stripping the
 * Cloudinary delivery prefix — ".../cloud/image/upload/v<version>/".
 */
final class CloudinaryImage
{
    public static function deleteByUrl(?string $url): void
    {
        if ($url === null || $url === '') {
            return;
        }

        $path = self::pathFromUrl($url);

        if ($path === null) {
            return;
        }

        // Asset cleanup is best-effort: a failed destroy must never block the
        // DB write that triggered it (an orphaned cloud file is recoverable,
        // a failed API call is not).
        try {
            Storage::disk('cloudinary')->delete($path);
        } catch (\Throwable $e) {
            // Ignored by design.
        }
    }

    /**
     * Converts a delivered Cloudinary image URL back to the storage path the
     * cloudinary disk understands (e.g.
     * https://res.cloudinary.com/asrnesf6/image/upload/v1789/listing-photos/X/a.jpg
     * -> listing-photos/X/a.jpg).
     */
    public static function pathFromUrl(string $url): ?string
    {
        $path = parse_url($url, PHP_URL_PATH);

        if ($path === null
            || ! preg_match('#/image/upload/(?:v\d+/)?(.+)$#i', $path, $matches)) {
            return null;
        }

        return $matches[1];
    }
}