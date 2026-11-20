<?php

namespace App\Http\Controllers;

use App\Models\Buyer;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\SearchLog;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

class AnalyticsController extends Controller
{
    public function index(Request $request)
    {
        $now = now();
        $filters = $request->validate([
            'range' => ['nullable', Rule::in(['week', 'today', '7', '30', 'custom'])],
            'from' => ['exclude_unless:range,custom', 'required', 'date_format:Y-m-d'],
            'to' => ['exclude_unless:range,custom', 'required', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
        $range = $filters['range'] ?? 'week';
        $localNow = $now->copy()->timezone('Asia/Manila');
        $searchStart = match ($range) {
            'today' => $localNow->copy()->startOfDay(),
            '7', '30' => $localNow->copy()->subDays((int) $range - 1)->startOfDay(),
            'custom' => Carbon::parse($filters['from'], 'Asia/Manila')->startOfDay(),
            default => $now->copy()->startOfWeek(),
        };
        $searchEnd = $range === 'custom'
            ? Carbon::parse($filters['to'], 'Asia/Manila')->endOfDay()->min($localNow)
            : $now;
        $monthStart = $now->copy()->startOfMonth();
        $trendStart = $monthStart->copy()->subMonths(11);

        // Group in SQL rather than downloading every search or registration.
        $searches = SearchLog::query()->whereNotNull('SRCH_KEYWORD')->whereRaw("TRIM(SRCH_KEYWORD) <> ''");
        $rankedSearches = (clone $searches)->whereBetween('SRCH_CREATED_AT', [
            $searchStart->copy()->timezone($now->timezone), $searchEnd->copy()->timezone($now->timezone),
        ])
            ->selectRaw('LOWER(TRIM(SRCH_KEYWORD)) as keyword, COUNT(*) as total')
            ->groupBy('keyword')->orderByDesc('total')->orderBy('keyword');
        $topSearches = (clone $rankedSearches)->limit(10)->get();
        $allSearches = $request->boolean('all') || $request->query('export') === 'csv'
            ? $rankedSearches->get() : collect();

        $registrations = User::whereBetween('USR_CREATED_AT', [$monthStart, $now])
            ->selectRaw('DAY(USR_CREATED_AT) as day, COUNT(*) as total')->groupBy('day')->get();
        $growthLabels = [];
        $growthValues = [];
        // Calendar-day buckets include days 29-31, which a fixed four-week chart misses.
        for ($day = 1; $day <= $now->day; $day += 7) {
            $end = min($day + 6, $now->day);
            $growthLabels[] = $now->format('M').' '.$day.'–'.$end;
            $growthValues[] = (int) $registrations->filter(fn ($row) => $row->day >= $day && $row->day <= $end)->sum('total');
        }

        // Observed posting activity, not a claim about crop seasons or forecasts.
        $monthly = Listing::whereBetween('LST_CREATED_AT', [$trendStart, $now])
            ->selectRaw("DATE_FORMAT(LST_CREATED_AT, '%Y-%m') as month_key, COALESCE(NULLIF(TRIM(LST_CROP_ICON), ''), 'Unspecified crop') as crop, COUNT(*) as total")
            ->groupBy('month_key', 'crop')
            ->orderByDesc('total')->orderBy('crop')->get()->groupBy('month_key');
        $monthlyTrends = [];
        for ($month = $trendStart->copy(); $month->lte($monthStart); $month->addMonth()) {
            $rows = $monthly->get($month->format('Y-m'), collect());
            $monthlyTrends[] = [
                'month' => $month->format('M Y'),
                'crop' => $rows->first()?->crop,
                'top_count' => (int) ($rows->first()?->total ?? 0),
                'total' => (int) $rows->sum('total'),
            ];
        }

        $data = [
            'totalUsers' => User::count(),
            'totalFarmers' => Farmer::whereHas('farms', fn ($q) => $q->where('FRM_STATUS', 'APPROVED'))
                ->whereHas('buyer.user', fn ($q) => $q->where('USR_STATUS', 'ACTIVE')->where('USR_IS_SELLER', 1))->count(),
            'totalBuyers' => Buyer::count(),
            // Match the public feed: expired active listings remain visible with a freshness notice.
            'totalListings' => Listing::where('LST_AVAILABILITY', 'ACTIVE')->where('LST_STATUS', '!=', 'NOT_AVAILABLE')->count(),
            'totalReports' => Report::open()->count(),
            'searchesToday' => (clone $searches)->whereBetween('SRCH_CREATED_AT', [$localNow->copy()->startOfDay()->timezone($now->timezone), $now])->count(),
            'topSearches' => $topSearches,
            'growthLabels' => $growthLabels,
            'growthValues' => $growthValues,
            'monthlyTrends' => $monthlyTrends,
            'weekLabel' => $searchStart->format('M j').' – '.($range === 'custom' ? $filters['to'] : $localNow->format('M j, Y')),
            'range' => $range,
            'filters' => $filters,
            'allSearches' => $allSearches,
            'monthLabel' => $now->format('F Y'),
            'asOf' => $localNow,
        ];

        if ($request->query('export') === 'csv') {
            return $this->export($data);
        }

        return view('analytics', $data);
    }

    private function export(array $data)
    {
        return response()->streamDownload(function () use ($data) {
            $out = fopen('php://output', 'w');
            $row = function (array $values) use ($out) {
                fputcsv($out, array_map(function ($value) {
                    return is_string($value) && preg_match('/^\s*[=+@-]|^[\t\r\n]/u', $value)
                        ? "'".$value : $value;
                }, $values), ',', '"', '');
            };
            $row(['System Analytics', $data['asOf']->toIso8601String()]);
            foreach (['Total users' => 'totalUsers', 'Active farmers' => 'totalFarmers', 'Registered buyers' => 'totalBuyers',
                'Visible listings' => 'totalListings', 'Searches today' => 'searchesToday', 'Pending reports' => 'totalReports'] as $label => $key) {
                $row([$label, $data[$key]]);
            }
            $row([]);
            $row(['Search term', 'Searches', $data['weekLabel']]);
            foreach ($data['allSearches'] as $search) {
                $row([$search->keyword, (int) $search->total]);
            }
            $row([]);
            $row(['Registration period', 'New users']);
            foreach ($data['growthLabels'] as $index => $label) {
                $row([$label, $data['growthValues'][$index]]);
            }
            $row([]);
            $row(['Month', 'Top crop', 'Top crop listings', 'Total listings']);
            foreach ($data['monthlyTrends'] as $trend) {
                $row([$trend['month'], $trend['crop'], $trend['top_count'], $trend['total']]);
            }
            fclose($out);
        }, 'farmspot-analytics.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }
}
