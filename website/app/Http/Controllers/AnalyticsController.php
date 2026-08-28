<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\Listing;
use App\Models\Report;
use App\Models\Farmer;
use App\Models\Buyer;
use Illuminate\Support\Facades\DB;

class AnalyticsController extends Controller
{
    public function index()
    {
        // User distribution
        $userRoles = User::select(
                'USR_ROLE',
                DB::raw('COUNT(*) as total')
            )
            ->groupBy('USR_ROLE')
            ->get();

        // Report Status
        $reportStatus = Report::select(
                'RPT_STATUS',
                DB::raw('COUNT(*) as total')
            )
            ->groupBy('RPT_STATUS')
            ->get();

        // Crop Category Statistics
        $cropStats = DB::table('listing')
            ->join('crop_category','listing.CAT_ID','=','crop_category.CAT_ID')
            ->select(
                'crop_category.CAT_NAME',
                DB::raw('COUNT(*) as total')
            )
            ->groupBy('crop_category.CAT_NAME')
            ->get();

        return view('analytics', [

            'totalUsers' => User::count(),
            'totalFarmers' => Farmer::count(),
            'totalBuyers' => Buyer::count(),
            'totalListings' => Listing::count(),
            'totalReports' => Report::count(),

            'userRoles' => $userRoles,
            'reportStatus' => $reportStatus,
            'cropStats' => $cropStats,

        ]);
    }
}