<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;

class DemoFarmMarketExtrasSeeder extends Seeder
{
    public function run(): void
    {
        if (DB::table('listing')->where('LST_DESCRIPTION', 'LIKE', 'Demo extra %')->exists()) {
            $this->command->info('Demo extras already present. Skipping.');
            return;
        }

        $now = Carbon::now();

        $farmNames = [
            "Lolo Dado's Organics",
            'Tabunan Greens',
            'Tungkil Bounty Farm',
            'Cansaga Farm Fresh',
            'Mulao Highland Produce',
            'Buanoy Mountain Crops',
            'San Roque Veggies',
        ];

        $farms = [];
        foreach ($farmNames as $i => $name) {
            $farm = DB::table('farm')->where('FRM_NAME', $name)->first();
            if (! $farm) {
                $this->command->error("Demo farm not found: {$name}");
                return;
            }
            $farms[$i] = $farm;

            // 3 farm profile photos each (map pin thumbnail + farm profile gallery)
            for ($p = 1; $p <= 3; $p++) {
                DB::table('farm_photo')->insert([
                    'FPHOTO_ID' => $this->uid('farm_photo', 'FPHOTO_ID'),
                    'FPHOTO_FILE_PATH' => DemoPhotoUrls::farm('farm' . ($i + 1), 'f' . $p),
                    'FPHOTO_UPLOADED_AT' => $farm->FRM_CREATED_AT,
                    'FRM_ID' => $farm->FRM_ID,
                ]);
            }
        }

        $crops = [
            'pechay'  => ['name' => 'Pechay',  'cat' => 'LEAFVG'],
            'repolyo' => ['name' => 'Repolyo', 'cat' => 'LEAFVG'],
            'sayote'  => ['name' => 'Sayote',  'cat' => 'FRTVEG'],
            'squash'  => ['name' => 'Squash',  'cat' => 'FRTVEG'],
            'lettuce' => ['name' => 'Lettuce', 'cat' => 'LEAFVG'],
            'kamatis' => ['name' => 'Kamatis', 'cat' => 'FRTVEG'],
            'pipino'  => ['name' => 'Pipino',  'cat' => 'FRTVEG'],
            'bataw'   => ['name' => 'Bataw',   'cat' => 'LEGMES'],
            'beans'   => ['name' => 'Beans',   'cat' => 'LEGMES'],
            'sili'    => ['name' => 'Sili Spada', 'cat' => 'HRBSPC'],
        ];

        // farmIdx (0-6) for the 3rd listing of each crop
        $plan = [
            ['pechay',  1, 'AVAILABLE_NOW'],
            ['repolyo', 6, 'AVAILABLE_NOW'],
            ['sayote',  0, 'SOON_TO_HARVEST'],
            ['squash',  4, 'AVAILABLE_NOW'],
            ['lettuce', 3, 'AVAILABLE_NOW'],
            ['kamatis', 5, 'AVAILABLE_NOW'],
            ['pipino',  2, 'AVAILABLE_NOW'],
            ['bataw',   2, 'SOON_TO_HARVEST'],
            ['beans',   1, 'AVAILABLE_NOW'],
            ['sili',    6, 'AVAILABLE_NOW'],
        ];

        $descriptions = [
            'Demo extra Freshly harvested pechay, crisp leaves and ready to cook.',
            'Demo extra Large green repolyo heads, heavy and tight.',
            'Demo extra Sayote vine-ripened, gently handled from the farm.',
            'Demo extra Sweet native squash, deep orange flesh.',
            'Demo extra Garden lettuce, kept cold from harvest to sale.',
            'Demo extra Juicy sun-ripened kamatis, picked at peak sweetness.',
            'Demo extra Straight crisp pipino cucumbers, no blemishes.',
            'Demo extra Tender young bataw pods for dinengdeng.',
            'Demo extra Fresh string beans, snappy and sweet.',
            'Demo extra Sili spada batch, mildly spicy frying peppers.',
        ];

        foreach ($plan as $idx => $p) {
            [$slug, $farmIdx, $status] = $p;
            $farm = $farms[$farmIdx];

            // photo slot numbers guaranteed to exist on disk
            $available = in_array($slug, ['kamatis'], true)
                ? [1, 2, 3, 4, 5, 6, 7, 8]
                : ($slug === 'squash' ? [1, 2, 3, 4, 5, 7, 8, 9, 10] : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            // pick 5 varied shots: first two base + three fresh extras
            $keys = $slug === 'kamatis' ? [0, 1, 5, 6, 7] : [0, 1, 6, 7, 8];

            $lstId = $this->uid('listing', 'LST_ID');
            $made = $now->copy()->subHours(38 - $idx * 2)->subMinutes($idx * 3);

            $photoNums = array_map(fn ($k) => $available[$k], $keys);
            $primaryUrl = DemoPhotoUrls::crop($slug, 'k' . $photoNums[0]);

            DB::table('listing')->insert([
                'LST_ID' => $lstId,
                'LST_CROP_ICON' => $crops[$slug]['name'],
                'LST_STATUS' => $status,
                'LST_AVAILABILITY' => 'ACTIVE',
                'LST_HARVEST_DATE' => $status === 'SOON_TO_HARVEST'
                    ? $now->copy()->addDays(5)->toDateString()
                    : $now->copy()->addDay()->toDateString(),
                'LST_EXPIRY_DATE' => $made->copy()->addDays(3),
                'LST_IMAGE' => $primaryUrl,
                'LST_DESCRIPTION' => $descriptions[$idx],
                'LST_CREATED_AT' => $made,
                'LST_UPDATED_AT' => $made,
                'FMR_ID' => $farm->FMR_ID,
                'FRM_ID' => $farm->FRM_ID,
                'CAT_ID' => $crops[$slug]['cat'],
            ]);

            foreach ($photoNums as $n => $num) {
                DB::table('listing_photo')->insert([
                    'LPHOTO_ID' => $this->uid('listing_photo', 'LPHOTO_ID'),
                    'LPHOTO_FILE_PATH' => DemoPhotoUrls::crop($slug, 'k' . $num),
                    'LPHOTO_UPLOADED_AT' => $made,
                    'LPHOTO_IS_PRIMARY' => $n === 0 ? 1 : 0,
                    'LST_ID' => $lstId,
                ]);
            }
        }

        $this->command->info('Demo extras seeded: 21 farm photos, 10 more listings (50 photos).');
    }

    private function uid(string $table, string $column): string
    {
        do {
            $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
            $id = '';
            for ($i = 0; $i < 6; $i++) {
                $id .= $chars[random_int(0, strlen($chars) - 1)];
            }
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}