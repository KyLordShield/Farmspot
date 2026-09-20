<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class UploadDemoPhotos extends Command
{
    protected $signature = 'demo:upload-photos {--dry-run : Report what would change without uploading}';

    protected $description = 'Upload demo crop/farm photos to Cloudinary and remap the seeded URLs';

    private array $localBase = [
        'listing_photo' => 'LPHOTO_FILE_PATH',
        'listing' => 'LST_IMAGE',
        'farm_photo' => 'FPHOTO_FILE_PATH',
    ];

    public function handle(): int
    {
        $mapping = ['crops' => [], 'farms' => []];
        $updated = ['listing_photo' => 0, 'listing' => 0, 'farm_photo' => 0];

        // Crop photos: public/demo-crops/{slug}/k#.jpg
        $cropsDir = public_path('demo-crops');
        foreach (glob($cropsDir . '/*') as $cropDir) {
            if (! is_dir($cropDir)) {
                continue;
            }
            $slug = basename($cropDir);
            $mapping['crops'][$slug] = [];
            foreach (glob($cropDir . '/k*.jpg') as $file) {
                $name = basename($file);
                $old = 'http://127.0.0.1:8000/demo-crops/' . $slug . '/' . $name;
                $cloud = $this->upload("demo/crops/{$slug}/{$name}", $file);
                $mapping['crops'][$slug][pathinfo($name, PATHINFO_FILENAME)] = $cloud;
                $updated['listing_photo'] += $this->remap('listing_photo', $old, $cloud);
                $updated['listing'] += $this->remap('listing', $old, $cloud);
            }
        }

        // Farm photos: public/demo-farm-photos/{farmN}/f#.jpg
        $farmsDir = public_path('demo-farm-photos');
        foreach (glob($farmsDir . '/*') as $farmDir) {
            if (! is_dir($farmDir)) {
                continue;
            }
            $slug = basename($farmDir);
            $mapping['farms'][$slug] = [];
            foreach (glob($farmDir . '/f*.jpg') as $file) {
                $name = basename($file);
                $old = 'http://127.0.0.1:8000/demo-farm-photos/' . $slug . '/' . $name;
                $cloud = $this->upload("demo/farms/{$slug}/{$name}", $file);
                $mapping['farms'][$slug][pathinfo($name, PATHINFO_FILENAME)] = $cloud;
                $updated['farm_photo'] += $this->remap('farm_photo', $old, $cloud);
            }
        }

        file_put_contents(
            database_path('seeders/demo_photo_urls.json'),
            json_encode($mapping, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)
        );

        $this->info('Uploads complete. Database rows updated:');
        foreach ($updated as $table => $count) {
            $this->line("  {$table}: {$count}");
        }
        $this->info('Mapping saved to database/seeders/demo_photo_urls.json');

        return self::SUCCESS;
    }

    private function upload(string $path, string $source): string
    {
        if ($this->option('dry-run')) {
            return 'https://dry-run/' . $path;
        }

        Storage::disk('cloudinary')->put($path, $source);

        return Storage::disk('cloudinary')->url($path);
    }

    private function remap(string $table, string $oldUrl, string $newUrl): int
    {
        if ($this->option('dry-run')) {
            return 0;
        }

        $column = $this->localBase[$table];

        return DB::table($table)
            ->where($column, $oldUrl)
            ->update([$column => $newUrl]);
    }
}