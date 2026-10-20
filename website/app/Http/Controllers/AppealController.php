<?php

namespace App\Http\Controllers;

use App\Models\ReviewRequest;
use App\Services\ModerationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Re-evaluations for listings and accounts taken down by an admin.
 *
 * The appeal is tied to the takedown (a reason exists), not to any single
 * report. One pending appeal per target; a DENIED appeal stays denied until a
 * new takedown happens, at which point a fresh request is allowed.
 */
class AppealController extends Controller
{
    public function __construct(protected ModerationService $moderation)
    {
    }

    /**
     * The queue of appeals awaiting a decision, newest first.
     */
    public function index(Request $request)
    {
        $appeals = ReviewRequest::with(['user', 'listing.farm', 'account', 'decidedBy'])
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('RRQ_STATUS', $request->status);
            })
            ->orderByDesc('RRQ_CREATED_AT')
            ->orderByDesc('RRQ_ID')
            ->paginate(10)
            ->withQueryString();

        $counts = ReviewRequest::selectRaw('RRQ_STATUS, COUNT(*) as total')
            ->groupBy('RRQ_STATUS')
            ->pluck('total', 'RRQ_STATUS');

        return view('appeals', [
            'appeals' => $appeals,
            'counts' => $counts,
        ]);
    }

    public function show(string $id)
    {
        $appeal = ReviewRequest::with(['user', 'listing.farm', 'listing.category', 'account', 'decidedBy'])
            ->where('RRQ_ID', $id)
            ->firstOrFail();

        return view('appeals.show', [
            'appeal' => $appeal,
        ]);
    }

    /**
     * Approve the appeal: restore the target and dismiss reports against it.
     */
    public function approve(Request $request, string $id)
    {
        $appeal = ReviewRequest::where('RRQ_ID', $id)->firstOrFail();

        if (! $appeal->isPending()) {
            return redirect()->route('appeals.show', $appeal->RRQ_ID)
                ->with('error', 'This appeal has already been decided.');
        }

        $validated = $request->validate([
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            DB::transaction(function () use ($appeal, $validated, $request) {
                if ($appeal->RRQ_TARGET_TYPE === ReviewRequest::TARGET_LISTING) {
                    $listing = $appeal->listing()->firstOrFail();
                    $this->moderation->restoreListing($listing);
                    $targets = $this->moderation->targetsForListing($listing->LST_ID);
                } else {
                    $account = $appeal->account()->firstOrFail();
                    $this->moderation->restoreAccount($account);
                    $targets = $this->moderation->targetsForUser($account);
                }

                // The reporters are a separate audience from the owner who
                // appealed: their reports are about to be dismissed, and they
                // have been waiting too. Read them while they are still open.
                $this->notifyAffectedReporters($targets, 'Dismissed');

                $this->moderation->finishOpenReports($targets, 'Dismissed');

                $appeal->update([
                    'RRQ_STATUS' => ReviewRequest::STATUS_APPROVED,
                    'RRQ_ADMIN_NOTE' => $validated['note'] ?? null,
                    'RRQ_DECIDED_BY' => $request->user()->USR_ID,
                    'RRQ_DECIDED_AT' => now(),
                ]);

                try {
                    \App\Models\AuditLog::record(
                        'APPEAL_APPROVED',
                        sprintf('Appeal %s (target %s %s) approved', $appeal->RRQ_ID, $appeal->RRQ_TARGET_TYPE, $appeal->RRQ_TARGET_ID),
                        $request->user()->USR_ID
                    );
                } catch (\Throwable $e) {
                    Log::warning('[audit] APPEAL_APPROVED failed', ['rrq_id' => $appeal->RRQ_ID, 'message' => $e->getMessage()]);
                }

                try {
                    app(\App\Services\NotificationService::class)->notify(
                        $appeal->USR_ID,
                        'APPEAL_APPROVED',
                        'Your re-evaluation request was approved',
                        'Your listing or account has been restored. Thanks for reaching out.',
                        $appeal->RRQ_ID
                    );
                } catch (\Throwable $e) {
                    Log::warning('[notifications] APPEAL_APPROVED failed', ['rrq_id' => $appeal->RRQ_ID, 'message' => $e->getMessage()]);
                }
            });

            return redirect()->route('appeals')->with('success', 'Appeal approved and target restored.');
        } catch (\Throwable $e) {
            Log::error('[appeals] approve failed', ['rrq_id' => $id, 'message' => $e->getMessage()]);

            return redirect()->route('appeals.show', $id)->with('error', 'Could not approve the appeal. Please try again.');
        }
    }

    /**
     * Deny the appeal: keep target down; reports become Resolved; denial final.
     */
    public function deny(Request $request, string $id)
    {
        $appeal = ReviewRequest::where('RRQ_ID', $id)->firstOrFail();

        if (! $appeal->isPending()) {
            return redirect()->route('appeals.show', $appeal->RRQ_ID)
                ->with('error', 'This appeal has already been decided.');
        }

        $validated = $request->validate([
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            DB::transaction(function () use ($appeal, $validated, $request) {
                if ($appeal->RRQ_TARGET_TYPE === ReviewRequest::TARGET_LISTING) {
                    $listing = $appeal->listing()->firstOrFail();
                    $targets = $this->moderation->targetsForListing($listing->LST_ID);
                } else {
                    $account = $appeal->account()->firstOrFail();
                    $targets = $this->moderation->targetsForUser($account);
                }

                // Same as approve: the reporters whose reports this denial
                // resolves are told, one each, before the rows leave 'open'.
                $this->notifyAffectedReporters($targets, 'Resolved');

                $this->moderation->finishOpenReports($targets, 'Resolved');

                $appeal->update([
                    'RRQ_STATUS' => ReviewRequest::STATUS_DENIED,
                    'RRQ_ADMIN_NOTE' => $validated['note'] ?? null,
                    'RRQ_DECIDED_BY' => $request->user()->USR_ID,
                    'RRQ_DECIDED_AT' => now(),
                ]);

                try {
                    \App\Models\AuditLog::record(
                        'APPEAL_DENIED',
                        sprintf('Appeal %s (target %s %s) denied', $appeal->RRQ_ID, $appeal->RRQ_TARGET_TYPE, $appeal->RRQ_TARGET_ID),
                        $request->user()->USR_ID
                    );
                } catch (\Throwable $e) {
                    Log::warning('[audit] APPEAL_DENIED failed', ['rrq_id' => $appeal->RRQ_ID, 'message' => $e->getMessage()]);
                }

                try {
                    app(\App\Services\NotificationService::class)->notify(
                        $appeal->USR_ID,
                        'APPEAL_DENIED',
                        'Your re-evaluation request was denied',
                        'After a second look, we are keeping the decision in place.',
                        $appeal->RRQ_ID
                    );
                } catch (\Throwable $e) {
                    Log::warning('[notifications] APPEAL_DENIED failed', ['rrq_id' => $appeal->RRQ_ID, 'message' => $e->getMessage()]);
                }
            });

            return redirect()->route('appeals')->with('success', 'Appeal denied.');
        } catch (\Throwable $e) {
            Log::error('[appeals] deny failed', ['rrq_id' => $id, 'message' => $e->getMessage()]);

            return redirect()->route('appeals.show', $id)->with('error', 'Could not deny the appeal. Please try again.');
        }
    }

    /**
     * Tell the people whose reports this appeal decision closes, one each.
     *
     * The owner hears the verdict through APPEAL_APPROVED or APPEAL_DENIED and
     * is NOT a reporter here, so this is a different audience: the buyers who
     * filed against the target and were also waiting to hear something. One
     * notification per person, pointing at their newest report, so a reporter
     * who filed several times is one voice and one inbox entry.
     *
     * Must run BEFORE finishOpenReports(): once the rows move out of 'open'
     * they can no longer be found. A failure to notify is logged and swallowed
     * — the appeal decision itself has already been made and must not be rolled
     * back because a push could not be written.
     */
    private function notifyAffectedReporters(array $targets, string $status): void
    {
        [$title, $body] = $status === 'Dismissed'
            ? ['Your report was dismissed', 'We reviewed your report and did not act on it.']
            : ['Your report was resolved', 'We resolved your report. Thanks for flagging it.'];

        $told = [];

        foreach ($this->moderation->openReportsFor($targets) as $row) {
            if (! $row->USR_ID || isset($told[$row->USR_ID])) {
                continue;
            }

            $told[$row->USR_ID] = true;

            try {
                app(\App\Services\NotificationService::class)->notify(
                    $row->USR_ID,
                    'REPORT_UPDATE',
                    $title,
                    $body,
                    $row->RPT_ID
                );
            } catch (\Throwable $e) {
                Log::warning('[notifications] appeal reporter notification failed', [
                    'usr_id' => $row->USR_ID,
                    'rpt_id' => $row->RPT_ID,
                    'message' => $e->getMessage(),
                ]);
            }
        }
    }
}
