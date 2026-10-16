<?php

namespace App\Http\Controllers;

use App\Models\AdminPlanner;
use App\Models\AuditLog;
use App\Models\Buyer;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\ReviewRequest;
use App\Models\User;
use App\Services\MassReportService;
use App\Services\WeatherService;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

class DashboardController extends Controller
{
    /**
     * The admin's personal dashboard.
     *
     * The two panels that used to live here (a crop breakdown and an account
     * mix chart) described the marketplace; this one is meant to be the
     * moderator's own workspace. It keeps the headline counts and the recent
     * reports queue, and adds a calendar, a private notes/reminders list, a
     * "needs attention" strip, shortcuts and the admin's own recent activity.
     */
    public function index()
    {
        $adminId = Auth::user()->USR_ID;

        // The planner lives in a table created by a migration that a given
        // deployment may not have run yet. Rather than let a missing table 500
        // the whole dashboard, fall back to an empty planner and let the view
        // hide the add forms; the calendar's live tasks still render.
        $plannerReady = Schema::hasTable('admin_planner');

        $notes = collect();
        $events = collect();

        if ($plannerReady) {
            // Private to this admin. Done notes sink to the bottom, then undated
            // ones, then the rest by soonest due date.
            $notes = AdminPlanner::forUser($adminId)
                ->where('APL_TYPE', AdminPlanner::TYPE_NOTE)
                ->orderBy('APL_IS_DONE')
                ->orderByRaw('APL_DATETIME IS NULL')
                ->orderBy('APL_DATETIME')
                ->orderByDesc('APL_CREATED_AT')
                ->get();

            $events = AdminPlanner::forUser($adminId)
                ->where('APL_TYPE', AdminPlanner::TYPE_EVENT)
                ->orderBy('APL_DATETIME')
                ->get();
        }

        return view('dashboard', [
            'users' => User::count(),
            'buyers' => Buyer::count(),
            'farmers' => Farmer::count(),
            'listings' => Listing::count(),
            'reports' => Report::where('RPT_STATUS', 'New')->count(),

            'recentUsers' => User::orderBy('USR_CREATED_AT', 'desc')->take(5)->get(),

            'recentListings' => Listing::orderBy('LST_CREATED_AT', 'desc')->take(5)->get(),

            'recentReports' => Report::with(['user', 'listing'])
                ->orderBy('RPT_CREATED_AT', 'desc')
                ->take(5)
                ->get(),

            'notes' => $notes,
            'events' => $events,
            'calendarItems' => $this->calendarItems($adminId, $notes, $events),
            'plannerReady' => $plannerReady,

            'newReports' => Report::where('RPT_STATUS', 'New')->count(),
            'flaggedTargets' => app(MassReportService::class)->openFlaggedTargetCount(),
            'pendingSellerRequests' => Farm::where('FRM_STATUS', 'PENDING_REVIEW')->count(),
            'pendingAppeals' => ReviewRequest::where('RRQ_STATUS', ReviewRequest::STATUS_PENDING)->count(),

            'recentActivity' => AuditLog::where('USR_ID', $adminId)
                ->orderByDesc('AUD_CREATED_AT')
                ->take(6)
                ->get(),

            // Best-effort. WeatherService returns null when the forecast is
            // unavailable (offline, disabled), and the view renders a quiet
            // fallback rather than an empty panel.
            'weather' => app(WeatherService::class)->current(),
        ]);
    }

    /**
     * Everything the calendar draws, as a flat list the browser groups by day.
     *
     * Three kinds of item share one shape ({date, type, title, ...}):
     *   - event : an admin-created calendar event
     *   - note  : an undated-free reminder that carries a due date
     *   - task  : live FarmSpot work (new reports, pending requests/appeals)
     *             aggregated per day, so a busy day reads as one chip with a
     *             count rather than a hundred entries.
     *
     * Tasks are pulled for a window around the current month (one month either
     * side) so navigating the calendar shows nearby activity without scanning
     * the whole history. Personal events and reminders are always included.
     */
    private function calendarItems(string $adminId, $notes, $events): array
    {
        $items = [];

        foreach ($events as $event) {
            if (! $event->APL_DATETIME) {
                continue;
            }

            $items[] = [
                'date' => $event->APL_DATETIME->format('Y-m-d'),
                'type' => 'event',
                'title' => $event->APL_TITLE,
                'meta' => $event->APL_BODY,
                'url' => null,
                'id' => $event->APL_ID,
            ];
        }

        foreach ($notes as $note) {
            if ($note->APL_IS_DONE || ! $note->APL_DATETIME) {
                continue;
            }

            $items[] = [
                'date' => $note->APL_DATETIME->format('Y-m-d'),
                'type' => 'note',
                'title' => $note->APL_TITLE,
                'meta' => 'Reminder',
                'url' => null,
                'id' => $note->APL_ID,
            ];
        }

        $start = now()->startOfMonth()->subMonth();
        $end = now()->endOfMonth()->addMonth();

        $reportsByDay = Report::where('RPT_STATUS', 'New')
            ->whereBetween('RPT_CREATED_AT', [$start, $end])
            ->selectRaw('DATE(RPT_CREATED_AT) as day, COUNT(*) as total')
            ->groupBy('day')
            ->pluck('total', 'day');

        foreach ($reportsByDay as $day => $total) {
            $items[] = [
                'date' => $day,
                'type' => 'task',
                'title' => $total.' '.Str::plural('new report', $total),
                'meta' => 'Moderation queue',
                'url' => route('reports'),
                'id' => null,
            ];
        }

        $requestsByDay = Farm::where('FRM_STATUS', 'PENDING_REVIEW')
            ->whereBetween('FRM_CREATED_AT', [$start, $end])
            ->selectRaw('DATE(FRM_CREATED_AT) as day, COUNT(*) as total')
            ->groupBy('day')
            ->pluck('total', 'day');

        foreach ($requestsByDay as $day => $total) {
            $items[] = [
                'date' => $day,
                'type' => 'task',
                'title' => $total.' '.Str::plural('seller request', $total),
                'meta' => 'Awaiting review',
                'url' => route('seller-requests'),
                'id' => null,
            ];
        }

        $appealsByDay = ReviewRequest::where('RRQ_STATUS', ReviewRequest::STATUS_PENDING)
            ->whereBetween('RRQ_CREATED_AT', [$start, $end])
            ->selectRaw('DATE(RRQ_CREATED_AT) as day, COUNT(*) as total')
            ->groupBy('day')
            ->pluck('total', 'day');

        foreach ($appealsByDay as $day => $total) {
            $items[] = [
                'date' => $day,
                'type' => 'task',
                'title' => $total.' '.Str::plural('appeal', $total),
                'meta' => 'Awaiting decision',
                'url' => route('appeals'),
                'id' => null,
            ];
        }

        return $items;
    }
}
