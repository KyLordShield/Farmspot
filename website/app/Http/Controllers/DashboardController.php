<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\Buyer;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\Whitelist;

use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    public function index()
    {
        $cropStats = DB::table('listing')
            ->join('crop_category', 'listing.CAT_ID', '=', 'crop_category.CAT_ID')
            ->select(
                'crop_category.CAT_NAME',
                DB::raw('COUNT(*) as total')
            )
            ->groupBy('crop_category.CAT_NAME')
            ->orderByDesc('total')
            ->get();

$associationOfficer = User::where('USR_ROLE', 'ADMIN')->first();

return view('dashboard', [

    'users' => User::count(),
    'buyers' => Buyer::count(),
    'farmers' => Farmer::count(),
    'listings' => Listing::count(),
    'reports' => Report::where('RPT_STATUS','New')->count(),
    'whitelist' => Whitelist::count(),

    'recentUsers' => User::orderBy('USR_CREATED_AT','desc')->take(5)->get(),

    'recentListings' => Listing::orderBy('LST_CREATED_AT','desc')->take(5)->get(),

    'recentReports' => Report::with(['user','listing'])
                             ->orderBy('RPT_CREATED_AT','desc')
                             ->take(5)
                             ->get(),

    'cropStats' => $cropStats,

    'associationOfficer' => $associationOfficer,

]);
    }
}