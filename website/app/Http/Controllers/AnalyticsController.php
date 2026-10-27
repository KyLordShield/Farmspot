<?php

namespace App\Http\Controllers;

use App\Models\Buyer;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\SearchLog;
use App\Models\User;

class AnalyticsController extends Controller
{
    public function index()
    {
        $now = now();
        $weekStart = $now->copy()->startOfWeek();
        $monthStart = $now->copy()->startOfMonth();
        $trendStart = $monthStart->copy()->subMonths(11);

        // Group in SQL rather than downloading every search or registration.
        $searches = SearchLog::query()->whereNotNull('SRCH_KEYWORD')->whereRaw("TRIM(SRCH_KEYWORD) <> ''");
        $topSearches = (clone $searches)->whereBetween('SRCH_CREATED_AT', [$weekStart, $now])
            ->selectRaw('LOWER(TRIM(SRCH_KEYWORD)) as keyword, COUNT(*) as total')
            ->groupBy('keyword')->orderByDesc('total')->orderBy('keyword')->limit(8)->get();

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

        return view('analytics', [
            'totalUsers' => User::count(),
            'totalFarmers' => Farmer::whereHas('farms', fn ($q) => $q->where('FRM_STATUS', 'APPROVED'))
                ->whereHas('buyer.user', fn ($q) => $q->where('USR_STATUS', 'ACTIVE')->where('USR_IS_SELLER', 1))->count(),
            'totalBuyers' => Buyer::count(),
            // Match the public feed: expired active listings remain visible with a freshness notice.
            'totalListings' => Listing::where('LST_AVAILABILITY', 'ACTIVE')->where('LST_STATUS', '!=', 'NOT_AVAILABLE')->count(),
            'totalReports' => Report::open()->count(),
            'searchesToday' => (clone $searches)->whereBetween('SRCH_CREATED_AT', [$now->copy()->startOfDay(), $now])->count(),
            'topSearches' => $topSearches,
            'growthLabels' => $growthLabels,
            'growthValues' => $growthValues,
            'monthlyTrends' => $monthlyTrends,
            'weekLabel' => $weekStart->format('M j').' – '.$now->format('M j, Y'),
            'monthLabel' => $now->format('F Y'),
            'asOf' => $now->format('M j, Y, g:i a').' '.config('app.timezone'),
        ]);
    }
}
