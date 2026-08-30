<?php

namespace App\Http\Controllers;

use App\Models\Report;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    public function index(Request $request)
    {
        $reports = Report::with(['user', 'listing'])
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('RPT_STATUS', $request->status);
            })
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $q->where('RPT_REASON', 'like', '%' . $request->search . '%')
                      ->orWhereHas('user', function ($uq) use ($request) {
                          $uq->where('USR_NAME', 'like', '%' . $request->search . '%')
                             ->orWhere('USR_EMAIL', 'like', '%' . $request->search . '%');
                      })
                      ->orWhereHas('listing', function ($lq) use ($request) {
                          $lq->where('LST_ID', 'like', '%' . $request->search . '%');
                      });
                });
            })
            ->orderBy('RPT_CREATED_AT', 'desc')
            ->paginate(10)
            ->withQueryString();

        $counts = Report::selectRaw('RPT_STATUS, COUNT(*) as total')
            ->groupBy('RPT_STATUS')
            ->pluck('total', 'RPT_STATUS');

        return view('reports', compact('reports', 'counts'));
    }

    public function show($id)
    {
        $report = Report::with(['user', 'listing.category', 'listing.farm', 'listing.farmer.buyer.user'])
            ->where('RPT_ID', $id)
            ->firstOrFail();

        return view('reports.show', compact('report'));
    }

    public function updateStatus(Request $request, $id)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:New,Reviewing,Resolved,Dismissed'],
        ]);

        $report = Report::findOrFail($id);

        $report->update([
            'RPT_STATUS' => $validated['status'],
        ]);

        return redirect()->route('reports')->with('success', 'Report status updated successfully.');
    }
}