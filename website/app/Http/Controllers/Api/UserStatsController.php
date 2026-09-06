<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ContactLog;
use App\Models\FarmVisitLog;
use App\Models\SearchLog;
use Illuminate\Http\Request;

class UserStatsController extends Controller
{
    /**
     * Buyer activity totals for the mobile Profile screen's stat row
     * (Searches / Farm Visited / Contact Made). Counts the real rows logged
     * for the authenticated user across search_log, farm_visit_log, and
     * contact_log.
     */
    public function show(Request $request)
    {
        $userId = $request->user()->USR_ID;

        return response()->json([
            'searches' => SearchLog::where('USR_ID', $userId)->count(),
            'farms_visited' => FarmVisitLog::where('USR_ID', $userId)->count(),
            'contacts_made' => ContactLog::where('USR_ID', $userId)->count(),
        ]);
    }
}