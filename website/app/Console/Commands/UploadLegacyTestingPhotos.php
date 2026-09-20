<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class UploadLegacyTestingPhotos extends Command
{
    protected $signature = 'demo:upload-testing-photos';

    protected $description = 'Upload the legacy testing-crops photos to Cloudinary and remap seller demo listings';

    public function handle(): int
    {
        $dir = public_path('testing-crops');
        if (! is_dir($dir)) {
            $this->error('website/public/testing-crops not found.');
            return self::FAILURE;
        }

        $photos = 0;
        $listings = 0;

        foreach (glob($dir . '/*.jpg') as $file) {
            $name = basename($file);
            $oldUrl = 'http://127.0.0.1:8000/testing-crops/' . $name;

            Storage::disk('cloudinary')->put("demo/testing/{$name}", $file);
            $cloudUrl = Storage::disk('cloudinary')->url("demo/testing/{$name}");

            $photos += DB::table('listing_photo')
                ->where('LPHOTO_FILE_PATH', $oldUrl)
                ->update(['LPHOTO_FILE_PATH' => $cloudUrl]);

            $listings += DB::table('listing')
                ->where('LST_IMAGE', $oldUrl)
                ->update(['LST_IMAGE' => $cloudUrl]);
        }

        $this->info("Legacy photos uploaded. listing_photo rows: {$photos}, listing images: {$listings}");

        return self::SUCCESS;
    }
}