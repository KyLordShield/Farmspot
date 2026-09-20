<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Carbon\Carbon;

class DemoFarmMarketSeeder extends Seeder
{
    public function run(): void
    {
        if (DB::table('user')->where('USR_EMAIL', 'demo.seller1@farmspot.test')->exists()) {
            $this->command->info('Demo data already present. Skipping.');
            return;
        }

        $now = Carbon::now();

        $farms = [
            ['name' => "Lolo Dado's Organics",     'desc' => 'Small organic family farm, Sudlon II hills.',
                'barangay' => 'Sudlon II, Cebu City',  'lat' => 10.3350, 'lng' => 123.8140],
            ['name' => 'Tabunan Greens',          'desc' => 'Cool climate leafy greens from Tabunan.',
                'barangay' => 'Tabunan, Cebu City',    'lat' => 10.3275, 'lng' => 123.7990],
            ['name' => 'Tungkil Bounty Farm',     'desc' => 'Pick fresh fruit veggies in Minglanilla.',
                'barangay' => 'Tungkil, Minglanilla',  'lat' => 10.2498, 'lng' => 123.7652],
            ['name' => 'Cansaga Farm Fresh',      'desc' => 'Neighbor farm garden, Cansaga river flats.',
                'barangay' => 'Cansaga, Consolacion',  'lat' => 10.4090, 'lng' => 123.9635],
            ['name' => 'Mulao Highland Produce',  'desc' => 'Highland veggies from the Liloan hills.',
                'barangay' => 'Mulao, Liloan',         'lat' => 10.4209, 'lng' => 123.9884],
            ['name' => 'Buanoy Mountain Crops',   'desc' => 'Terraced gardens up in Balamban.',
                'barangay' => 'Buanoy, Balamban',      'lat' => 10.4712, 'lng' => 123.7200],
            ['name' => 'San Roque Veggies',       'desc' => 'Backyard farm by the Talisay shoreline.',
                'barangay' => 'San Roque, Talisay',    'lat' => 10.2317, 'lng' => 123.8390],
        ];

        $owners = [
            ['name' => 'Dado Bantugan',  'email' => 'demo.seller1@farmspot.test', 'mobile' => '+639170000001', 'address' => 'Sudlon II, Cebu City'],
            ['name' => 'Neneng Casio',   'email' => 'demo.seller2@farmspot.test', 'mobile' => '+639170000002', 'address' => 'Tabunan, Cebu City'],
            ['name' => 'Rodel Pama',     'email' => 'demo.seller3@farmspot.test', 'mobile' => '+639170000003', 'address' => 'Tungkil, Minglanilla'],
            ['name' => 'Marites Gucor',  'email' => 'demo.seller4@farmspot.test', 'mobile' => '+639170000004', 'address' => 'Cansaga, Consolacion'],
            ['name' => 'Boy Leyson',     'email' => 'demo.seller5@farmspot.test', 'mobile' => '+639170000005', 'address' => 'Mulao, Liloan'],
            ['name' => 'Inday Sabilao',  'email' => 'demo.seller6@farmspot.test', 'mobile' => '+639170000006', 'address' => 'Buanoy, Balamban'],
            ['name' => 'Tony Ocao',      'email' => 'demo.seller7@farmspot.test', 'mobile' => '+639170000007', 'address' => 'San Roque, Talisay'],
        ];

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

        // listing plan: crop => [farmIndex (0-based), status, description]
        $plan = [
            ['pechay',  0, 'AVAILABLE_NOW',      'Freshly picked pechay, washed and bunched. Ideal for chopsuey or sinigang.'],
            ['pechay',  6, 'SOON_TO_HARVEST',    'Second batch of pechay ready by mid-week. Safer busdako.'],
            ['repolyo', 1, 'AVAILABLE_NOW',      'Tight, heavy repolyo heads. Good for atol or lumpia.'],
            ['repolyo', 4, 'SOON_TO_HARVEST',    'Tancy repolyo heads firming up, harvest in about a week.'],
            ['sayote',  5, 'AVAILABLE_NOW',      'Fresh sayote, mild and crunchy. Per piece.'],
            ['sayote',  3, 'AVAILABLE_NOW',      'Sayote from the cooler hillside plots.'],
            ['squash',  0, 'AVAILABLE_NOW',      'Native squash, sweet and yellow. Best for ginataan.'],
            ['squash',  2, 'AVAILABLE_NOW',      'Large kalabasa squash, freshly cut.'],
            ['lettuce', 1, 'AVAILABLE_NOW',      'Crisp iceberg lettuce, cold-chained this morning.'],
            ['lettuce', 6, 'SOON_TO_HARVEST',    'Iceberg lettuce maturing nicely, available in a few days.'],
            ['kamatis', 2, 'AVAILABLE_NOW',      'Sun-ripened kamatis, sweet and juicy. Per kilo.'],
            ['kamatis', 3, 'AVAILABLE_NOW',      'Farm fresh kamatis for salsa and everyday cooking.'],
            ['pipino',  0, 'AVAILABLE_NOW',      'Crisp pipino, great for salads and pickles.'],
            ['pipino',  1, 'AVAILABLE_NOW',      'Fresh green pipino, no wax.'],
            ['bataw',   4, 'AVAILABLE_NOW',      'Tender bataw pods, perfect for dinengdeng.'],
            ['bataw',   5, 'SOON_TO_HARVEST',    'Bataw climbing nicely, harvest soon.'],
            ['beans',   3, 'AVAILABLE_NOW',      'Snappy green beans, stringed and ready.'],
            ['beans',   6, 'AVAILABLE_NOW',      'Garden-fresh beans, sweet and tender.'],
            ['sili',    2, 'AVAILABLE_NOW',      'Sili spada, mild-long frying chili. Per bundle.'],
            ['sili',    4, 'SOON_TO_HARVEST',    'Finger chili ripening, spicy batch in a few days.'],
        ];

        $created = [];
        for ($i = 0; $i < 7; $i++) {
            $usrId = $this->uid('user', 'USR_ID');
            $buyId = $this->uid('buyer', 'BUY_ID');
            $fmrId = $this->uid('farmer', 'FMR_ID');
            $frmId = $this->uid('farm', 'FRM_ID');

            $createdAt = $now->copy()->subDays(80 - $i * 2)->subMinutes(10 + $i);

            DB::table('user')->insert([
                'USR_ID' => $usrId,
                'USR_NAME' => $owners[$i]['name'],
                'USR_EMAIL' => $owners[$i]['email'],
                'USR_PASSWORD' => Hash::make('password123'),
                'USR_MOBILE_NUMBER' => $owners[$i]['mobile'],
                'USR_ADDRESS' => $owners[$i]['address'],
                'USR_PHOTO_PATH' => null,
                'USR_ROLE' => 'GENERAL_USER',
                'USR_IS_SELLER' => 1,
                'USR_STATUS' => 'ACTIVE',
                'USR_CREATED_AT' => $createdAt,
            ]);

            DB::table('buyer')->insert([
                'BUY_ID' => $buyId,
                'BUY_CURRENT_LATITUDE' => $farms[$i]['lat'],
                'BUY_CURRENT_LONGITUDE' => $farms[$i]['lng'],
                'BUY_LOC_UPDATED_AT' => $now,
                'USR_ID' => $usrId,
            ]);

            DB::table('farmer')->insert([
                'FMR_ID' => $fmrId,
                'FMR_SELLER_MODE_ACTIVE' => 1,
                'FMR_VERIFIED_AT' => $createdAt->copy()->addDays(1),
                'BUY_ID' => $buyId,
            ]);

            DB::table('farm')->insert([
                'FRM_ID' => $frmId,
                'FRM_NAME' => $farms[$i]['name'],
                'FRM_DESCRIPTION' => $farms[$i]['desc'],
                'FRM_BARANGAY' => $farms[$i]['barangay'],
                'FRM_LATITUDE' => $farms[$i]['lat'],
                'FRM_LONGITUDE' => $farms[$i]['lng'],
                'FRM_STATUS' => 'APPROVED',
                'FRM_PIN_ACTIVE' => 1,
                'FRM_VERIFICATION_DOC_PATH' => null,
                'FRM_CREATED_AT' => $createdAt,
                'FMR_ID' => $fmrId,
            ]);

            $created[] = ['frmId' => $frmId, 'fmrId' => $fmrId];
        }

        foreach ($plan as $idx => $p) {
            [$slug, $farmIdx, $status, $description] = $p;
            $farm = $created[$farmIdx];
            $lstId = $this->uid('listing', 'LST_ID');
            $made = $now->copy()->subHours(46 - $idx * 2)->subMinutes($idx * 7);

            $photoCount = $slug === 'squash' ? 5 : 6;
            // even-indexed listing takes first 4, odd takes the last 4 (varies the gallery)
            $listB = $idx % 2 === 1;
            $photoNums = $listB
                ? [$photoCount - 3, $photoCount - 2, $photoCount - 1, $photoCount]
                : [1, 2, 3, 4];

            $primary = $listB ? $photoNums[0] : $photoNums[0];
            $primaryUrl = DemoPhotoUrls::crop($slug, 'k' . $primary);

            $harvest = $status === 'SOON_TO_HARVEST'
                ? $made->copy()->addDays(3 + $idx % 5)
                : $made->copy()->addDay();

            DB::table('listing')->insert([
                'LST_ID' => $lstId,
                'LST_CROP_ICON' => $crops[$slug]['name'],
                'LST_STATUS' => $status,
                'LST_AVAILABILITY' => 'ACTIVE',
                'LST_HARVEST_DATE' => $harvest->toDateString(),
                'LST_EXPIRY_DATE' => $made->copy()->addDays(3),
                'LST_IMAGE' => $primaryUrl,
                'LST_DESCRIPTION' => $description,
                'LST_CREATED_AT' => $made,
                'LST_UPDATED_AT' => $made,
                'FMR_ID' => $farm['fmrId'],
                'FRM_ID' => $farm['frmId'],
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

        $this->command->info('Demo farm market seeded: 7 farms, 20 listings, 80 photos.');
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