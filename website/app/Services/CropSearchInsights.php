<?php

namespace App\Services;

use App\Models\Listing;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;

final class CropSearchInsights
{
    public const DEMO_AS_OF = '2026-11-21 12:00:00';
    public const DEMO_BATCH = 'crop-insights-v1';

    public static function demoEnabled(): bool
    {
        return app()->environment(['local', 'staging', 'testing']) && config('farmspot.insights_demo', false);
    }

    public function snapshot(): array
    {
        $demo = self::demoEnabled();
        $now = $demo ? Carbon::parse(self::DEMO_AS_OF, 'Asia/Manila') : now('Asia/Manila');
        return Cache::remember(self::cacheKey($now, $demo), 300, fn () => $this->build($now, $demo));
    }

    public static function cacheKey(Carbon $now, bool $demo): string
    {
        return 'crop-search-insights:v3:'.($demo ? 'demo:' : 'live:').$now->format('Y-m-d');
    }

    private function build(Carbon $now, bool $demo): array
    {
        $month = $now->copy()->startOfMonth();
        $history = [];
        for ($year = 3; $year >= 1; $year--) {
            $start = $month->copy()->subYears($year);
            $history[$start->format('M Y')] = $this->aggregate($start, $start->copy()->addMonth(), $demo);
        }

        $recentStart = $now->copy()->subDays(30);
        $previous = $this->aggregate($now->copy()->subDays(60), $recentStart, $demo);
        $recent = $this->aggregate($recentStart, $now, $demo);
        $current = $this->aggregate($month, $now, $demo);
        $asMap = static function (array $period): array {
            $period['crops'] = (object) $period['crops'];

            return $period;
        };
        $futureMonths = [];
        for ($offset = 1; $offset <= 3; $offset++) {
            $target = $month->copy()->addMonths($offset);
            $samples = [];
            for ($year = 1; $year <= 3; $year++) {
                $start = $target->copy()->subYears($year);
                $samples[$start->format('M Y')] = $asMap($this->aggregate($start, $start->copy()->addMonth(), $demo));
            }
            $futureMonths[] = [
                'month_key' => $target->format('Y-m'),
                'month' => $target->format('F Y'),
                'history' => $samples,
            ];
        }

        $input = [
            'history' => array_map($asMap, $history), 'previous' => $asMap($previous),
            'recent' => $asMap($recent), 'current' => $asMap($current), 'future_months' => $futureMonths,
        ];
        $process = new Process([config('farmspot.insights_python'), base_path('analytics/search_interest.py')]);
        if (PHP_OS_FAMILY === 'Windows') {
            // Windows web workers may lack access to Python's startup entropy.
            // This scoring process needs the same startup setting in live and demo mode.
            $process->setEnv(['PYTHONHASHSEED' => '42']);
        }
        $process->setTimeout(10)->setInput(json_encode($input, JSON_THROW_ON_ERROR));
        $scored = json_decode($process->mustRun()->getOutput(), true, flags: JSON_THROW_ON_ERROR);

        $weeks = [];
        $weekRanges = [];
        $weekStart = $now->copy()->startOfWeek();
        for ($week = 3; $week >= 0; $week--) {
            $start = $weekStart->copy()->subWeeks($week);
            $end = $start->copy()->addDays(6);
            $weekRanges[] = $start->format('M j').'–'.$end->format(
                $start->isSameMonth($end) ? 'j' : 'M j'
            );
            $weeks[$start->format('M j')] = $this->aggregate($start, $week ? $start->copy()->addWeek() : $now, $demo);
        }

        // Compare completed weeks so a partial Monday does not imply a drop.
        $weeklyPeriods = array_values($weeks);
        $last = $weeklyPeriods[2];
        $before = $weeklyPeriods[1];
        $trending = [];
        foreach ($last['crops'] as $crop => $count) {
            $previousCount = $before['crops'][$crop] ?? 0;
            $trending[] = [
                'crop' => $crop,
                'count' => $count,
                'change' => $count - $previousCount,
                'points' => array_map(fn ($period) => $period['crops'][$crop] ?? 0, $weeklyPeriods),
            ];
        }
        usort($trending, fn ($a, $b) => $b['count'] <=> $a['count'] ?: $b['change'] <=> $a['change']
            ?: strcasecmp($a['crop'], $b['crop']));

        $display = array_slice(array_values(array_filter($scored['predictions'], fn ($row) => $row['confidence'] !== null)), 0, 5);
        $months = [];
        for ($offset = 5; $offset >= 0 && $display; $offset--) {
            $start = $month->copy()->subMonths($offset);
            $months[$start->format('M')] = $offset
                ? $this->aggregate($start, $start->copy()->addMonth(), $demo) : $current;
        }
        foreach ($display as &$prediction) {
            $crop = $prediction['crop'];
            $prediction['history'] = array_map(
                fn ($period) => $period['pairs'] ? ($period['crops'][$crop] ?? 0) / $period['pairs'] : null,
                $months,
            );
        }
        unset($prediction);

        $listings = $demo
            ? DB::table('insight_demo_listings')->where('batch', self::DEMO_BATCH)->pluck('crop')
            : Listing::query()->where('LST_AVAILABILITY', 'ACTIVE')->where('LST_STATUS', 'AVAILABLE_NOW')
                ->where('LST_EXPIRY_DATE', '>=', $now->copy()->timezone(config('app.timezone')))
                ->pluck('LST_CROP_ICON');
        $supply = $listings->filter()->map([CropSearchTerm::class, 'normalize'])->countBy();
        $crops = array_unique([...array_keys($recent['crops']), ...$supply->keys()->all()]);
        $comparison = array_map(fn ($crop) => [
            'crop' => (string) $crop, 'searchers' => $recent['crops'][$crop] ?? 0, 'listings' => $supply->get($crop, 0),
        ], $crops);
        usort($comparison, fn ($a, $b) => $b['searchers'] <=> $a['searchers'] ?: strcasecmp($a['crop'], $b['crop']));

        $comparisonRows = array_slice($comparison, 0, 5);
        $highestSupply = $comparison;
        usort($highestSupply, fn ($a, $b) => $b['listings'] <=> $a['listings']
            ?: $a['searchers'] <=> $b['searchers'] ?: strcasecmp($a['crop'], $b['crop']));
        foreach (array_slice($highestSupply, 0, 2) as $row) {
            if ($row['listings'] > 0 && ! in_array($row['crop'], array_column($comparisonRows, 'crop'), true)) {
                $comparisonRows[] = $row;
            }
        }

        return [
            'updated_at' => $now->toIso8601String(), 'month' => $now->format('F'), 'month_key' => $now->format('Y-m'),
            'is_demo' => $demo, 'predictions' => $display, 'forecast' => $scored['forecast'],
            'trending' => array_values(array_filter($trending, fn ($row) => $row['count'] >= ($trending[4]['count'] ?? 0))),
            'week_labels' => array_keys($weeks),
            'week_ranges' => $weekRanges,
            'comparison' => $comparisonRows,
        ];
    }

    private function aggregate(Carbon $start, Carbon $end, bool $demo): array
    {
        $date = $demo ? 'searched_at' : 'SRCH_CREATED_AT';
        $word = $demo ? 'crop' : 'SRCH_KEYWORD';
        $user = $demo ? 'searcher' : 'USR_ID';
        $zone = config('app.timezone');
        $rows = DB::table($demo ? 'insight_demo_searches' : 'search_log')
            ->when($demo, fn ($query) => $query->where('batch', self::DEMO_BATCH))
            ->where($date, '>=', $start->copy()->timezone($zone))
            ->where($date, '<', $end->copy()->timezone($zone))
            ->whereNotNull($word)
            ->select($word, $user)->selectRaw('COUNT(*) as searches')
            ->groupBy($word, $user)->cursor();

        $total = 0;
        $users = [];
        foreach ($rows as $row) {
            $crop = CropSearchTerm::normalize($row->$word);
            if ($crop === '') continue;
            $total += (int) $row->searches;
            $users[$crop][$row->$user] = true;
        }

        $counts = array_map('count', $users);
        return ['total' => $total, 'pairs' => array_sum($counts), 'crops' => $counts];
    }
}
