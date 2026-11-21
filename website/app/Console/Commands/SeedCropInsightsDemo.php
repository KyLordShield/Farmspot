<?php

namespace App\Console\Commands;

use App\Services\CropSearchInsights;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Random\Engine\Mt19937;
use Random\Randomizer;

class SeedCropInsightsDemo extends Command
{
    protected $signature = 'insights:demo {--undo : Remove the demo batch}';

    protected $description = 'Create or remove the isolated Crop Insights demonstration dataset';

    public function handle(): int
    {
        if (! app()->environment(['local', 'staging', 'testing'])) {
            $this->error('This command is available only in local, staging, and testing.');
            return self::FAILURE;
        }

        $now = Carbon::parse(CropSearchInsights::DEMO_AS_OF, 'Asia/Manila');
        DB::transaction(function () use ($now) {
            foreach (['insight_demo_searches', 'insight_demo_listings'] as $table) {
                DB::table($table)->where('batch', CropSearchInsights::DEMO_BATCH)->delete();
            }
            if (! $this->option('undo')) {
                $this->seed($now);
            }
        });
        Cache::forget(CropSearchInsights::cacheKey($now, true));
        $this->info($this->option('undo') ? 'Demo batch removed.' : 'Demo batch ready. Set FARMSPOT_INSIGHTS_DEMO=true to display it.');

        return self::SUCCESS;
    }

    private function seed(Carbon $now): void
    {
        $random = new Randomizer(new Mt19937(32026));
        $crops = [
            'bok choy' => [11, 12, 1, 2], 'cabbage' => [11, 12, 1, 2],
            'chayote' => [10, 11, 12], 'cucumber' => [3, 4, 5],
            'tomato' => [11, 12, 1, 2], 'eggplant' => [4, 5, 6],
            'sitaw' => [6, 7, 8], 'ampalaya' => [4, 5, 6],
            'squash' => [10, 11, 12], 'lettuce' => [11, 12, 1, 2],
            'chili pepper' => [4, 10], 'carrots' => [12, 1, 2],
            'kamote' => [5, 6, 7], 'corn' => [6, 7, 8], 'ginger' => [8, 9, 10],
        ];
        $rows = [];
        $append = function (string $crop, int $user, Carbon $date) use (&$rows) {
            $rows[] = [
                'batch' => CropSearchInsights::DEMO_BATCH, 'crop' => $crop, 'searcher' => $user,
                'searched_at' => $date->copy()->timezone(config('app.timezone'))->toDateTimeString(),
            ];
        };
        $tied = ['cucumber', 'eggplant', 'carrots', 'corn'];
        $tieWeek = $now->copy()->startOfWeek()->subWeek();
        for ($month = Carbon::parse('2024-01-01', 'Asia/Manila'); $month->lte($now); $month->addMonth()) {
            $key = $month->format('Y-m');
            if ($key === '2025-06') continue;
            $base = [2024 => 8, 2025 => 40, 2026 => 105][$month->year];
            foreach ($crops as $crop => $peak) {
                if (in_array($crop, ['ginger', 'lettuce', 'tomato'], true)) continue;
                if ($crop === 'squash' && $month->year === 2026 && $month->month >= 10) continue;
                $fraction = in_array($month->month, $peak, true) ? 35 : 17;
                $users = max(1, intdiv($base * $fraction, 100));
                $users = min($base, max(1, $users + $random->getInt(-2, 4)));
                $draw = $random->pickArrayKeys(array_fill(1, $base, true), $users);
                foreach ($draw as $user) {
                    $date = $month->copy()->addDays($random->getInt(0, min(19, $month->daysInMonth - 1)))->addHours(9);
                    if ($date->gte($now) || (in_array($crop, $tied, true) && $date->betweenIncluded($tieWeek, $tieWeek->copy()->addDays(6)->endOfDay()))) continue;
                    $append($crop === 'bok choy' && $user % 2 ? '  Bok Choy ' : ($crop === 'bok choy' ? 'pechay' : $crop), $user, $date);
                }
            }
        }

        // Give each forecast month a different leader in two historical years.
        foreach ([12 => 'squash', 1 => 'tomato', 2 => 'lettuce'] as $month => $crop) {
            foreach ([$month === 12 ? 2024 : 2025, $month === 12 ? 2025 : 2026] as $year) {
                $date = Carbon::create($year, $month, 14, 9, 0, 0, 'Asia/Manila');
                $size = [2024 => 8, 2025 => 40, 2026 => 105][$year];
                for ($user = 1; $user <= $size; $user++) {
                    $append($crop, $user, $date);
                }
            }
        }

        // An extra November-only baseline supplies a third prior observation.
        foreach ([2023 => 8, 2024 => 8, 2025 => 40] as $year => $size) {
            $date = Carbon::create($year, 11, 12, 9, 0, 0, 'Asia/Manila');
            for ($user = 1; $user <= $size; $user++) {
                if ($user <= max(5, (int) ($size / 2))) $append('tomato', $user, $date);
                if ($year === 2025 && $user <= 8) $append('lettuce', $user, $date);
                if ($year === 2023) {
                    foreach (['bok choy', 'cabbage', 'chayote', 'squash'] as $crop) $append($crop, $user, $date);
                }
            }
        }
        foreach (['tomato' => 95, 'lettuce' => 55, 'ginger' => 44] as $crop => $users) {
            for ($user = 1; $user <= $users; $user++) $append($crop, $user, $now->copy()->subDays(2 + $user % 14));
        }
        foreach ($tied as $crop) {
            for ($user = 1; $user <= 12; $user++) $append($crop, $user, $tieWeek->copy()->addHours(10));
        }
        for ($i = 0; $i < 100; $i++) $append('radish', 1, $now->copy()->subDay());
        foreach (array_chunk($rows, 200) as $chunk) DB::table('insight_demo_searches')->insert($chunk);

        $listings = [];
        foreach (['tomato' => 2, 'lettuce' => 3, 'ginger' => 1, 'bok choy' => 8, 'cabbage' => 36, 'squash' => 24] as $crop => $count) {
            for ($i = 0; $i < $count; $i++) $listings[] = ['batch' => CropSearchInsights::DEMO_BATCH, 'crop' => $crop];
        }
        DB::table('insight_demo_listings')->insert($listings);
    }
}
