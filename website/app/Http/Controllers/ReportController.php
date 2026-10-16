<?php

namespace App\Http\Controllers;

use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Report;
use App\Models\ReportAction;
use App\Models\User;
use App\Services\MassReportService;
use App\Services\ModerationService;
use App\Services\NotificationService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class ReportController extends Controller
{
    /**
     * The enforcement steps that must carry a reason.
     *
     * Every one of these leaves something the owner can see gone: a listing
     * off sale, an account that can no longer sign in. The reason is not
     * paperwork — it is the sentence the app shows them and the grounds they
     * contest in a re-evaluation request. Recording it at the moment of the
     * takedown is the only time it is reliably known; reconstructing it later
     * from a report is guesswork.
     *
     * MESSAGE_HIDDEN is deliberately absent. Hiding a message is not a takedown
     * of the sender's account or listing and has no re-evaluation path, so
     * forcing a reason there would only train moderators to type filler.
     */
    private const REASON_REQUIRED_ACTIONS = [
        'LISTING_TAKEN_DOWN',
        'SELLER_DEACTIVATED',
        'FARMER_ACCOUNT_DEACTIVATED',
        'FARMER_LISTINGS_TAKEN_DOWN',
        'ACCOUNT_DEACTIVATED',
    ];
    /**
     * The moderator queue.
     *
     * Reports arrive from the app now, against four different subjects, so the
     * list has to answer "what was reported" without a moderator opening each
     * row. A LISTING report names the crop, a MESSAGE report shows the opening
     * of the text, and a FARMER or USER report names the person.
     */
    public function index(Request $request)
    {
        $reports = Report::with(['user', 'listing', 'farmer.buyer.user', 'message', 'reportedUser'])
            // Lets the list show which reports have actually been acted on, so
            // "Resolved" is distinguishable from "we did something about it".
            ->withCount(['liveActions as live_actions_count'])
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('RPT_STATUS', $request->status);
            })
            ->when($request->filled('type'), function ($query) use ($request) {
                $query->where('RPT_TARGET_TYPE', $request->type);
            })
            // ?flagged=1 shows only the targets a wave of reports has already
            // marked. The queue still lists everything by default; this is the
            // "where is the fire" view, not a separate inbox.
            ->when($request->filled('flagged'), function ($query) {
                $query->whereNotNull('RPT_FLAGGED_AT');
            })
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $term = '%'.$request->search.'%';
                    $q->where('RPT_REASON', 'like', $term)
                      ->orWhere('RPT_DETAILS', 'like', $term)
                      ->orWhere('RPT_TARGET_ID', 'like', $term)
                      ->orWhereHas('user', function ($uq) use ($term) {
                          $uq->where('USR_NAME', 'like', $term)
                             ->orWhere('USR_EMAIL', 'like', $term);
                      })
                      ->orWhereHas('listing', function ($lq) use ($term) {
                          $lq->where('LST_ID', 'like', $term);
                      });
                });
            })
            ->orderByRaw("FIELD(RPT_STATUS, 'New', 'Reviewing', 'Resolved', 'Dismissed')")
            ->orderBy('RPT_CREATED_AT', 'desc')
            ->paginate(10)
            ->withQueryString();

        $counts = Report::selectRaw('RPT_STATUS, COUNT(*) as total')
            ->groupBy('RPT_STATUS')
            ->pluck('total', 'RPT_STATUS');

        // By subject type as well as by status. A queue that is mostly spam
        // messages wants a different response from one that is mostly fake
        // listings, and the status counts alone cannot tell them apart.
        $typeCounts = Report::selectRaw('RPT_TARGET_TYPE, COUNT(*) as total')
            ->groupBy('RPT_TARGET_TYPE')
            ->pluck('total', 'RPT_TARGET_TYPE');

        // How many open reports currently carry the mass-report flag, so the
        // queue can say "three targets need a look" without the moderator
        // filtering by hand. Counted on open rows only: a flagged report that
        // was since dealt with is not still asking for attention.
        $flaggedCount = Report::open()->whereNotNull('RPT_FLAGGED_AT')->count();

        return view('reports', [
            'reports' => $reports,
            // Every report, not the filtered $reports->total(): the card says
            // "Total reports" and has to keep meaning that while a filter is on.
            'totalReports' => Report::count(),
            'counts' => $counts,
            'typeCounts' => $typeCounts,
            'flaggedCount' => $flaggedCount,
            // Distinct targets, not reports: one account that ten people
            // complained about is one mass report, and that is what the
            // overview card and the sidebar alert count.
            'flaggedTargetCount' => app(MassReportService::class)->openFlaggedTargetCount(),
            'threshold' => app(MassReportService::class)->threshold(),
            'actionLabels' => Report::ACTION_LABELS,
        ]);
    }

    /**
     * The mass-report alerts, grouped by what was reported.
     *
     * The flat queue lists reports one per row, which is exactly what hides a
     * wave: ten rows about the same account read as ten unrelated complaints.
     * This page collapses them to one row per target with the distinct reporter
     * count, so the question "who is being piled on" is answered before a
     * moderator opens anything.
     *
     * Open, flagged rows only. Resolving the reports clears RPT_FLAGGED_AT, so
     * an alert leaves this page the moment the queue deals with it, and a
     * genuinely new wave can raise it again.
     */
    public function flagged()
    {
        $rows = Report::query()
            ->open()
            ->whereNotNull('RPT_FLAGGED_AT')
            ->select('RPT_TARGET_TYPE', 'RPT_TARGET_ID')
            ->selectRaw('COUNT(*) as open_count')
            ->selectRaw('COUNT(DISTINCT USR_ID) as reporter_count')
            ->selectRaw('MIN(RPT_CREATED_AT) as first_at')
            ->selectRaw('MAX(RPT_CREATED_AT) as last_at')
            ->groupBy('RPT_TARGET_TYPE', 'RPT_TARGET_ID')
            ->orderByDesc('reporter_count')
            ->orderByDesc('last_at')
            ->get();

        $alerts = $rows->map(function ($row) {
            $subject = $this->describeTarget($row->RPT_TARGET_TYPE, $row->RPT_TARGET_ID);

            return [
                'type' => $row->RPT_TARGET_TYPE,
                'id' => $row->RPT_TARGET_ID,
                'type_label' => $this->targetTypeLabel($row->RPT_TARGET_TYPE),
                'name' => $subject['name'],
                'subtitle' => $subject['subtitle'],
                'url' => $subject['url'],
                'icon' => $subject['icon'],
                'open_count' => (int) $row->open_count,
                'reporter_count' => (int) $row->reporter_count,
                'first_at' => $row->first_at,
                'last_at' => $row->last_at,
            ];
        });

        return view('reports.flagged', [
            'alerts' => $alerts,
            'threshold' => app(MassReportService::class)->threshold(),
        ]);
    }

    /**
     * One flagged target in full: the subject, and every distinct person who
     * reported it with the reason they gave.
     *
     * Deliberately read-only. Enforcing happens on a single report's page,
     * where the moderator sees exactly which complaint they are acting on and
     * the audit trail records it against that report. This page exists to answer
     * "is this a real pattern or one person shouting", and a number alone cannot
     * do that — the reasons can.
     */
    public function flaggedTarget($type, $id)
    {
        if (! in_array($type, Report::TARGET_TYPES, true)) {
            abort(404);
        }

        $reports = Report::with([
            'user',
            'listing',
            'farmer.buyer.user',
            'message.sender',
            'reportedUser',
        ])
            ->where('RPT_TARGET_TYPE', $type)
            ->where('RPT_TARGET_ID', $id)
            ->open()
            ->whereNotNull('RPT_FLAGGED_AT')
            ->orderBy('RPT_CREATED_AT', 'desc')
            ->get();

        // The target could have been resolved since the alerts page was loaded.
        // Sending the moderator back to the list beats showing an empty page
        // they would have to interpret.
        if ($reports->isEmpty()) {
            return redirect()->route('reports.flagged')
                ->with('error', 'That mass-report alert is no longer open.');
        }

        // One row per person, not per report: the whole point of the threshold
        // is distinct voices, so the count a moderator reads here has to be the
        // same shape as the count that tripped the flag. A reporter who filed
        // more than once still appears once, with all of their reasons.
        $byReporter = $reports
            ->groupBy('USR_ID')
            ->map(function ($group) {
                $group = $group->sortBy('RPT_CREATED_AT')->values();

                return [
                    'reporter' => $group->first()->user,
                    'reports' => $group,
                    'reasons' => $group->map(fn ($r) => $r->reasonLabel())->unique()->values(),
                    'count' => $group->count(),
                    'latest_at' => $group->max('RPT_CREATED_AT'),
                ];
            })
            ->sortByDesc('count')
            ->values();

        // The enforcement steps on offer for this target, computed from the
        // newest open report. Acting here resolves the whole cluster, so the
        // options are the target's, not a single report's.
        $representative = $reports->first();

        return view('reports.flagged_target', [
            'type' => $type,
            'id' => $id,
            'subject' => $this->describeTarget($type, $id),
            'reports' => $reports,
            'byReporter' => $byReporter,
            'options' => $this->availableActions($representative),
            'actionLabels' => Report::ACTION_LABELS,
            'threshold' => app(MassReportService::class)->threshold(),
        ]);
    }

    /**
     * Human-readable name for a report target type, for the alert list.
     */
    private function targetTypeLabel(string $type): string
    {
        return match ($type) {
            Report::TARGET_LISTING => 'Crop listing',
            Report::TARGET_MESSAGE => 'Message',
            Report::TARGET_FARMER => 'Farmer / seller',
            Report::TARGET_USER => 'User',
            default => $type,
        };
    }

    /**
     * Name and link for whatever a report points at, for the alert list.
     *
     * Resolved from the type/id pair rather than from a Report model so the
     * grouped query — which never loads a full report row — can use it too. The
     * link goes to the subject's own admin page when one exists (a listing, a
     * user), and is null for a message, which has no standalone page.
     */
    private function describeTarget(string $type, string $id): array
    {
        switch ($type) {
            case Report::TARGET_LISTING:
                $listing = Listing::with(['farm', 'category'])->find($id);

                if (! $listing) {
                    return ['name' => 'Deleted listing', 'subtitle' => $id, 'url' => null, 'icon' => 'basket'];
                }

                $parts = array_filter([
                    $listing->farm?->FRM_NAME,
                    $listing->category?->CAT_NAME,
                ]);

                return [
                    'name' => ($listing->LST_CROP_ICON ?: 'Listing').' ('.$listing->LST_ID.')',
                    'subtitle' => $parts ? implode(' · ', $parts) : 'Crop listing',
                    'url' => route('listings.show', $listing->LST_ID),
                    'icon' => 'basket',
                ];

            case Report::TARGET_FARMER:
                $farmer = Farmer::with('buyer.user')->find($id);
                $user = $farmer?->buyer?->user;

                return [
                    'name' => $user?->USR_NAME ?? 'Unknown farmer',
                    'subtitle' => 'Farmer / seller'.($user?->USR_EMAIL ? ' · '.$user->USR_EMAIL : ''),
                    'url' => $user ? route('users.show', $user->USR_ID) : null,
                    'icon' => 'person-badge',
                ];

            case Report::TARGET_USER:
                $user = User::find($id);

                return [
                    'name' => $user?->USR_NAME ?? 'Unknown user',
                    'subtitle' => 'User account'.($user?->USR_EMAIL ? ' · '.$user->USR_EMAIL : ''),
                    'url' => $user ? route('users.show', $user->USR_ID) : null,
                    'icon' => 'person',
                ];

            case Report::TARGET_MESSAGE:
                $message = Message::with('sender')->find($id);

                return [
                    'name' => 'Message '.$id,
                    'subtitle' => $message?->sender?->USR_NAME
                        ? 'Sent by '.$message->sender->USR_NAME
                        : 'Chat message',
                    'url' => null,
                    'icon' => 'chat-quote',
                ];
        }

        return ['name' => $id, 'subtitle' => $type, 'url' => null, 'icon' => 'flag'];
    }

    public function show($id)
    {
        $report = Report::with([
            'user',
            'listing.category',
            'listing.farm',
            'listing.farmer.buyer.user',
            'farmer.buyer.user',
            // The message's sender, to name who sent the reported text. The
            // conversation is not loaded: Conversation has no farm() relation,
            // and the listing context on the report already covers it.
            'message.sender',
            'reportedUser',
            'actions.moderator',
            'actions.revertedBy',
        ])
            ->where('RPT_ID', $id)
            ->firstOrFail();

        $report->setRelation('actions', $report->actions->sortBy('RAC_SEQ')->values());

        // Opening a report IS the moderator reading it, so a New report moves to
        // Reviewing on the way in — no separate click to say "I am looking at
        // this". Done before the view is built so the status shown in the
        // dropdown is already the new one, and done with a direct update rather
        // than updateStatus() so opening a report never sends the reporter a
        // notification: no buyer is told anything just because a moderator
        // glanced at the queue.
        if ($report->RPT_STATUS === 'New') {
            Report::where('RPT_ID', $report->RPT_ID)
                ->where('RPT_STATUS', 'New')
                ->update(['RPT_STATUS' => 'Reviewing', 'RPT_UPDATED_AT' => now()]);
            $report->RPT_STATUS = 'Reviewing';
            $report->RPT_UPDATED_AT = now();
        }

        // The view renders what these return and the endpoints re-check them, so
        // a moderator is never offered a button that would then be refused. The
        // labels are passed in rather than read off the model in the template:
        // Blade compiles without a namespace, so a bare Report:: in a view
        // resolves to the global class and 500s the page.
        return view('reports.show', [
            'report' => $report,
            'options' => $this->availableActions($report),
            'blocked' => $this->blockedReasons($report),
            'actionLabels' => Report::ACTION_LABELS,
        ]);
    }

    /**
     * Apply one enforcement step to this report.
     *
     * Everything here is deliberately a human decision on a single report. A
     * report is a lead, not a verdict: there is no counter anywhere in this
     * class, because "three reports = suspended" would hand any one buyer the
     * power to bury a competitor by filing three reports against them.
     */
    public function applyAction(Request $request, $id, $action)
    {
        $report = $this->findWithSubjects($id);

        $result = $this->runAction($request, $report, $action);

        return redirect()->route('reports.show', $report->RPT_ID)
            ->with(isset($result['error']) ? 'error' : 'success', $result['error'] ?? $result['success']);
    }

    /**
     * Act on a whole mass-report target, from the alert drill-down.
     *
     * Same decision as acting on one report — one enforcement step, chosen by a
     * human, recorded against a report — but the entry point is the target.
     * A moderator who has just read the list of reporters should not have to
     * pick one report out of the cluster to hang the action on: the newest open
     * report carries the audit row, and finishOpenReports() then closes every
     * other report for the target, so the rest are not left dangling.
     */
    public function flaggedTargetAction(Request $request, $type, $id, $action)
    {
        if (! in_array($type, Report::TARGET_TYPES, true)) {
            abort(404);
        }

        // The representative report. Newest rather than oldest because the
        // queue is read newest-first, so this matches the row the moderator
        // most likely just looked at.
        $report = Report::with(['listing', 'farmer.buyer.user', 'reportedUser', 'user'])
            ->where('RPT_TARGET_TYPE', $type)
            ->where('RPT_TARGET_ID', $id)
            ->open()
            ->orderByDesc('RPT_CREATED_AT')
            ->first();

        if (! $report) {
            return redirect()->route('reports.flagged')
                ->with('error', 'That mass-report alert is no longer open.');
        }

        $result = $this->runAction($request, $report, $action);

        if (isset($result['error'])) {
            return redirect()->route('reports.flaggedTarget', [$type, $id])
                ->with('error', $result['error']);
        }

        return redirect()->route('reports.flagged')
            ->with('success', $result['success'].' Every open report on this target was resolved.');
    }

    /**
     * The shared body of both action entry points: confirm the step is on
     * offer, apply it, record it, finish the cluster, notify the reporter.
     *
     * Returns ['success' => phrase] or ['error' => phrase]. The callers own the
     * redirect because the two entry points land on different pages.
     */
    private function runAction(Request $request, Report $report, string $action): array
    {
        $option = $this->pickOption($this->availableActions($report), $action);
        if ($option === null) {
            return ['error' => $this->blockedReasons($report)[0]
                ?? "That action is not available on report #{$report->RPT_ID}."];
        }

        $validated = $request->validate([
            'note' => [
                in_array($action, self::REASON_REQUIRED_ACTIONS, true) ? 'required' : 'nullable',
                'string',
                'max:500',
            ],
        ]);

        $note = $validated['note'] ?? null;

        $previous = $this->apply($report, $action, $note);

        // The takedown finishes the reports it answers. Leaving the siblings of
        // this report open would leave the queue showing complaints about
        // something that has already been dealt with, which is how a moderator
        // ends up acting twice on the same problem. The acted report is closed
        // too, so a report that was New or Reviewing settles as Resolved rather
        // than sitting in the list as work in progress after the work is done.
        $targets = $this->targetsForAction($report, $action, $previous);

        // Everything open that this one decision is about to finish, read while
        // it is still open. It serves two masters: the other reporters get told
        // their report was closed, and undo can reopen exactly these rows rather
        // than guessing from the target later.
        $closing = app(ModerationService::class)->openReportsFor($targets);

        // One notification per distinct person, pointing at their newest report,
        // and never at the reporter being handled below — that person gets the
        // specific outcome from notifyReporter() and a second "resolved" ping
        // would be noise.
        $siblingReporters = [];
        foreach ($closing as $row) {
            if ($row->USR_ID === null || $row->USR_ID === $report->USR_ID) {
                continue;
            }
            $siblingReporters[$row->USR_ID] ??= $row->RPT_ID;
        }

        // What undo needs: the id and the prior status of every report this
        // closes. Recorded on the action because once the bulk update lands the
        // open state is gone and cannot be reconstructed.
        $previous['closed_reports'] = $closing->pluck('RPT_STATUS', 'RPT_ID')->all();

        $record = ReportAction::create([
            'RAC_ID' => $this->newActionId(),
            'RPT_ID' => $report->RPT_ID,
            'RAC_ACTION' => $action,
            'RAC_SUBJECT_TYPE' => Report::ENFORCEMENT[$report->RPT_TARGET_TYPE][$action]['subject'],
            'RAC_SUBJECT_ID' => $report->RPT_TARGET_ID,
            'RAC_PREV' => json_encode($previous),
            'RAC_NOTE' => $note,
            'RAC_BY' => $request->user()->USR_ID,
            'RAC_APPLIED_AT' => now(),
        ]);

        app(ModerationService::class)->finishOpenReports(
            $targets,
            'Resolved'
        );

        // Belt and braces for the message case and anything whose target pair
        // did not match its own row: the report the moderator just acted on is
        // closed no matter what the target enumeration returned.
        Report::where('RPT_ID', $report->RPT_ID)
            ->whereIn('RPT_STATUS', Report::OPEN_STATUSES)
            ->update(['RPT_STATUS' => 'Resolved', 'RPT_UPDATED_AT' => now()]);

        // The report the action was hung on gets the specific outcome...
        $this->notifyReporter($report, $record, applied: true);

        // ...and the rest of the cluster's reporters get one update each,
        // pointing at their own report.
        foreach ($siblingReporters as $usrId => $rptId) {
            $this->notifyReportResolved($usrId, $rptId);
        }

        return ['success' => $option['done']];
    }

    /**
     * Roll back the most recent action that is still in force.
     *
     * Nothing is ever deleted, so undo restores the recorded previous value
     * rather than rebuilding anything. Getting a takedown wrong is expected — a
     * real listing can look fake until a moderator checks it — so this has to be
     * one click, not a support ticket.
     */
    public function undoAction(Request $request, $id)
    {
        $report = $this->findWithSubjects($id);

        // Ordered by insertion, not by the clock. Two steps on one report are
        // normally applied from the same page seconds apart, and picking the
        // wrong one to roll back leaves the report in a state nobody asked for.
        $record = $report->liveActions()->orderByDesc('RAC_SEQ')->first();
        if (! $record) {
            return redirect()->route('reports.show', $report->RPT_ID)
                ->with('error', 'There is no action on this report to undo.');
        }

        $this->revert($report, $record);

        // The reports this action closed are put back too. The subject being
        // restored does not make the complaints about it go away, so leaving
        // them Resolved would show the queue as quieter than it is.
        $this->reopenClosedReports($record);

        $record->update([
            'RAC_REVERTED_AT' => now(),
            'RAC_REVERTED_BY' => $request->user()->USR_ID,
        ]);

        $this->notifyReporter($report, $record, applied: false);

        return redirect()->route('reports.show', $report->RPT_ID)
            ->with('success', "Undone: {$record->label()}. The subject was put back as it was.");
    }

    public function updateStatus(Request $request, $id)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:New,Reviewing,Resolved,Dismissed'],
        ]);

        $report = Report::findOrFail($id);

        // Read before the write. Without this, re-saving the status a moderator
        // already set looks like a change and would tell the reporter their
        // report was resolved every time anyone opened the dropdown.
        $previousStatus = $report->RPT_STATUS;

        // Compare-and-swap: the UPDATE only lands if the status is still what we
        // read a moment ago. Two moderators on the same report is normal at
        // shift change, and with a plain update() both would write, both would
        // believe they had acted, and the reporter would get two notifications
        // for one outcome. This is the difference between "notified once per
        // status change" being true under concurrency rather than only when one
        // person is clicking.
        $updated = Report::where('RPT_ID', $report->RPT_ID)
            ->where('RPT_STATUS', $previousStatus)
            ->update([
                'RPT_STATUS' => $validated['status'],
                // Stamped so the queue can show how long a report has been open.
                // The table predates Eloquent timestamps, so this is set by hand.
                'RPT_UPDATED_AT' => now(),
                // A finished report stops asking for attention, so the mass-report
                // flag is cleared with it. Reopening to New or Reviewing leaves
                // the flag alone; the next wave of reports can set it again once
                // the target is genuinely reported afresh.
                'RPT_FLAGGED_AT' => in_array($validated['status'], ['Resolved', 'Dismissed'], true)
                    ? null
                    : $report->RPT_FLAGGED_AT,
            ]);

        if (! $updated) {
            return redirect()->route('reports.show', $report->RPT_ID)
                ->with('error', 'Someone else just changed this status. Reload and try again.');
        }

        $this->notifyReporterOfStatus($report, $previousStatus, $validated['status']);

        return redirect()->route('reports')->with('success', 'Report status updated successfully.');
    }

    // ------------------------------------------------------------- enforcement

    /**
     * Every action that could be applied right now, with the copy the view needs.
     *
     * A subject can offer more than one. A farmer can be deactivated and have
     * their listings taken down as two independent decisions, and because each
     * is its own report_action row, undoing one does not disturb the other.
     */
    private function availableActions(Report $report): array
    {
        if ($report->RPT_STATUS === 'Dismissed') {
            return [];
        }

        $options = [];

        foreach (Report::ENFORCEMENT[$report->RPT_TARGET_TYPE] ?? [] as $action => $meta) {
            $subject = $this->subjectFor($report, $action);

            if ($subject === null) {
                continue;
            }

            if ($report->liveActions()->where('RAC_ACTION', $action)->exists()) {
                continue;
            }

            $blocked = $this->whyUnavailable($report, $action, $subject);
            if ($blocked !== null) {
                continue;
            }

            $options[] = [
                'action' => $action,
                'button' => $meta['button'],
                'subject' => $this->describeSubject($report, $action),
                'done' => $this->describeOutcome($report, $action, $subject),
                // Whether this step needs a reason the owner will be shown. The
                // view marks the field required to match the same rule enforced
                // in applyAction(), so the browser does not offer a button that
                // the server is about to reject.
                'requires_reason' => in_array($action, self::REASON_REQUIRED_ACTIONS, true),
            ];
        }

        return $options;
    }

    /**
     * Plain reasons for anything not on offer.
     *
     * A missing button with no explanation is how a moderator ends up thinking
     * the queue cannot act at all, so the page always says which it is.
     */
    private function blockedReasons(Report $report): array
    {
        $reasons = [];

        if ($report->RPT_STATUS === 'Dismissed') {
            $reasons[] = 'This report was dismissed, so there is nothing to act on. Set it back to New or Reviewing to act on it.';

            return $reasons;
        }

        $available = collect($this->availableActions($report))->pluck('action')->all();

        foreach (Report::ENFORCEMENT[$report->RPT_TARGET_TYPE] ?? [] as $action => $meta) {
            if (in_array($action, $available, true)) {
                continue;
            }

            $subject = $this->subjectFor($report, $action);

            if ($subject === null) {
                $reasons[] = $this->missingSubjectReason($report, $action);
                continue;
            }

            $why = $this->whyUnavailable($report, $action, $subject);
            $reasons[] = $why ?? "{$meta['label']} has already been applied to this report.";
        }

        return array_values(array_unique(array_filter($reasons)));
    }

    /**
     * The record this action would change, or null if it cannot be resolved.
     */
    private function subjectFor(Report $report, string $action)
    {
        return match ($action) {
            'LISTING_TAKEN_DOWN' => Listing::find($report->RPT_TARGET_ID),
            'SELLER_DEACTIVATED' => $this->sellerFor($report),
            'FARMER_ACCOUNT_DEACTIVATED' => $this->accountBehind($report->farmer),
            'FARMER_LISTINGS_TAKEN_DOWN' => $report->farmer ?? Farmer::find($report->RPT_TARGET_ID),
            'ACCOUNT_DEACTIVATED' => $report->reportedUser ?? User::find($report->RPT_TARGET_ID),
            'MESSAGE_HIDDEN' => Message::find($report->RPT_TARGET_ID),
            default => null,
        };
    }

    /**
     * The account behind a farmer record. A farmer is not a person in this
     * schema — it is a row hanging off a buyer, which hangs off a user — so
     * "deactivate this farmer" is only meaningful as "deactivate that user".
     */
    private function accountBehind(?Farmer $farmer): ?User
    {
        if (! $farmer) {
            return null;
        }

        return $farmer->relationLoaded('buyer')
            ? $farmer->buyer?->user
            : User::whereHas('buyer', fn ($q) => $q->where('BUY_ID', $farmer->BUY_ID))->first();
    }

    /**
     * The user who posted a reported listing.
     */
    private function sellerFor(Report $report): ?User
    {
        $listing = Listing::find($report->RPT_TARGET_ID);
        if (! $listing) {
            return null;
        }

        $farmer = Farmer::with('buyer.user')->find($listing->FMR_ID);

        return $farmer?->buyer?->user;
    }

    private function whyUnavailable(Report $report, string $action, $subject): ?string
    {
        if ($action === 'LISTING_TAKEN_DOWN' && $subject->LST_AVAILABILITY === 'REMOVED') {
            return 'This listing is already off sale, so there is nothing to take down.';
        }

        if (str_ends_with($action, 'DEACTIVATED')) {
            if ($subject->USR_STATUS === 'DEACTIVATED') {
                return "{$subject->USR_NAME} is already deactivated.";
            }
        }

        if ($action === 'FARMER_LISTINGS_TAKEN_DOWN' && $this->activeListingsFor($report->farmer)->isEmpty()) {
            return 'This farmer has no listings on sale to take down.';
        }

        if ($action === 'MESSAGE_HIDDEN' && $subject->isHidden()) {
            return 'This message is already hidden.';
        }

        return null;
    }

    private function missingSubjectReason(Report $report, string $action): string
    {
        return match ($action) {
            'LISTING_TAKEN_DOWN' => 'This listing no longer exists.',
            'MESSAGE_HIDDEN' => 'This message no longer exists.',
            'SELLER_DEACTIVATED' => 'The seller who posted this listing could not be found.',
            'FARMER_ACCOUNT_DEACTIVATED' => 'There is no account behind this farmer record.',
            'FARMER_LISTINGS_TAKEN_DOWN' => 'This farmer record no longer exists.',
            default => 'This account no longer exists.',
        };
    }

    private function describeSubject(Report $report, string $action): string
    {
        return match ($action) {
            'LISTING_TAKEN_DOWN' => 'listing '.$report->RPT_TARGET_ID,
            'SELLER_DEACTIVATED' => $this->sellerFor($report)?->USR_NAME ?? 'the seller',
            'FARMER_ACCOUNT_DEACTIVATED' => $this->accountBehind($report->farmer)?->USR_NAME ?? 'the farmer',
            'FARMER_LISTINGS_TAKEN_DOWN' => $this->activeListingsFor($report->farmer)->count().' active listing(s)',
            'ACCOUNT_DEACTIVATED' => $this->subjectFor($report, $action)?->USR_NAME ?? 'the account',
            'MESSAGE_HIDDEN' => 'the message',
            default => $report->RPT_TARGET_ID,
        };
    }

    private function describeOutcome(Report $report, string $action, $subject): string
    {
        return match ($action) {
            'LISTING_TAKEN_DOWN' => "Listing {$report->RPT_TARGET_ID} is off sale. It is hidden from the feed and from search, and can be restored.",
            'SELLER_DEACTIVATED' => $subject->USR_NAME.' is deactivated and their access tokens are revoked, so they are signed out of the app. This can be restored.',
            'FARMER_ACCOUNT_DEACTIVATED' => $subject->USR_NAME.' is deactivated and signed out of the app. This can be restored.',
            'FARMER_LISTINGS_TAKEN_DOWN' => 'This farmer now has no listings on sale. Their account is untouched, and this can be restored.',
            'ACCOUNT_DEACTIVATED' => $subject->USR_NAME.' is deactivated and signed out of the app. This can be restored.',
            'MESSAGE_HIDDEN' => 'The message is hidden from the conversation. It is kept in the database so this can be restored.',
            default => 'Done.',
        };
    }

    /**
     * Which (type, id) targets this action just finished, so their open reports
     * can be closed with it.
     *
     * Deliberately resolves through the subject that was actually changed, not
     * just the report's own target. Deactivating the seller behind a reported
     * listing is about the person, so reports filed against that person are
     * finished too — and vice versa for a farmer whose account and listings were
     * both touched.
     */
    private function targetsForAction(Report $report, string $action, array $previous): array
    {
        $moderation = app(ModerationService::class);

        return match ($action) {
            'LISTING_TAKEN_DOWN' => $moderation->targetsForListing($report->RPT_TARGET_ID),
            'SELLER_DEACTIVATED', 'FARMER_ACCOUNT_DEACTIVATED', 'ACCOUNT_DEACTIVATED' => ($user = $this->subjectFor($report, $action))
                ? $moderation->targetsForUser($user)
                : [],
            'FARMER_LISTINGS_TAKEN_DOWN' => $report->farmer
                ? $moderation->targetsForFarmer($report->farmer, array_keys($previous['listings'] ?? []))
                : [],
            'MESSAGE_HIDDEN' => [[Report::TARGET_MESSAGE, $report->RPT_TARGET_ID]],
            default => [],
        };
    }

    // ------------------------------------------------------------------ apply

    /**
     * Make the change and return what has to be put back to undo it.
     */
    private function apply(Report $report, string $action, ?string $reason): array
    {
        $subject = $this->subjectFor($report, $action);

        return match ($action) {
            'LISTING_TAKEN_DOWN' => $this->takeDownListings(
                Listing::where('LST_ID', $subject->LST_ID),
                $reason
            ),
            'SELLER_DEACTIVATED' => $this->deactivateAccount($subject, $reason),
            'FARMER_ACCOUNT_DEACTIVATED' => $this->deactivateAccount($subject, $reason),
            'FARMER_LISTINGS_TAKEN_DOWN' => $this->takeDownListings($this->activeListingsFor($report->farmer), $reason),
            'ACCOUNT_DEACTIVATED' => $this->deactivateAccount($subject, $reason),
            'MESSAGE_HIDDEN' => $this->hideMessage($subject),
            default => [],
        };
    }

    /**
     * Off sale, reversibly — and with a reason the owner can read and appeal.
     *
     * REMOVED is the same soft state the seller's own delete-listing action uses,
     * and it is what every buyer-facing query filters on, so this genuinely
     * removes it from the app rather than just flagging it.
     *
     * LST_TAKEDOWN_REASON is what makes the removal a takedown rather than a
     * self-delete, and LST_HIDDEN_BY_TAKEDOWN remembers that WE hid this row: an
     * account restored later brings back only what an admin removal took down,
     * never a listing the farmer had deleted for their own reasons.
     */
    private function takeDownListings($listings, ?string $reason): array
    {
        // Takes a builder or a collection. Iterating a Builder directly yields
        // one array of raw column values per row, not models, so $listing would
        // be an array and every property read below would fail. Asking for the
        // models is what makes the rest of this method work either way.
        if ($listings instanceof Builder) {
            $listings = $listings->get();
        }

        $previous = [];

        foreach ($listings as $listing) {
            $previous[$listing->LST_ID] = $listing->LST_AVAILABILITY;
            $listing->update([
                'LST_AVAILABILITY' => 'REMOVED',
                'LST_TAKEDOWN_REASON' => $reason,
                'LST_TAKEDOWN_AT' => now(),
                'LST_HIDDEN_BY_TAKEDOWN' => true,
                'LST_UPDATED_AT' => now(),
            ]);
        }

        // Always keyed by listing id, even for a single listing, so undo reads
        // the same shape whether one row or a whole catalogue was affected.
        return ['listings' => $previous];
    }

    /**
     * Deactivate, and actually sign the person out.
     *
     * Setting USR_STATUS alone only blocks the *next* login: AuthController
     * checks it once, at login, and nothing revokes tokens already issued, so a
     * buyer who reported harassment and was then deactivated kept full API
     * access from an app that was already installed. Deleting the tokens is what
     * makes the button mean what it says.
     *
     * The reason is stored alongside, because a deactivation the owner cannot
     * understand is only slightly better than no explanation at all: the app
     * shows USR_TAKEDOWN_REASON at the refused login and offers the appeal path
     * only when there is a reason to appeal.
     */
    private function deactivateAccount(User $user, ?string $reason): array
    {
        $previous = ['USR_STATUS' => $user->USR_STATUS];

        $user->update([
            'USR_STATUS' => 'DEACTIVATED',
            'USR_TAKEDOWN_REASON' => $reason,
            'USR_TAKEDOWN_AT' => now(),
            'USR_HIDDEN_BY_TAKEDOWN' => true,
        ]);
        $user->tokens()->delete();

        return $previous;
    }

    private function hideMessage(Message $message): array
    {
        $previous = ['MSG_VISIBILITY' => $message->MSG_VISIBILITY];

        $message->update([
            'MSG_VISIBILITY' => 'HIDDEN',
            'MSG_HIDDEN_AT' => now(),
        ]);

        return $previous;
    }

    /**
     * Put back exactly what was there, not a hardcoded default.
     *
     * A listing can be NOT_AVAILABLE for an honest reason while it is being
     * reported, and restoring it to ACTIVE would put unsold produce back on
     * sale.
     */
    private function revert(Report $report, ReportAction $record): void
    {
        $previous = $record->previous();

        switch ($record->RAC_ACTION) {
            case 'LISTING_TAKEN_DOWN':
                Listing::where('LST_ID', $report->RPT_TARGET_ID)->update([
                    'LST_AVAILABILITY' => $previous['listings'][$report->RPT_TARGET_ID] ?? 'ACTIVE',
                    // Undone means it is no longer a takedown, so the reason and
                    // the marker go with the state. Leaving the reason behind
                    // would keep the listing in the "taken down, appealable"
                    // bucket in the app after a moderator put it back.
                    'LST_TAKEDOWN_REASON' => null,
                    'LST_TAKEDOWN_AT' => null,
                    'LST_HIDDEN_BY_TAKEDOWN' => false,
                    'LST_UPDATED_AT' => now(),
                ]);
                break;

            case 'SELLER_DEACTIVATED':
            case 'FARMER_ACCOUNT_DEACTIVATED':
            case 'ACCOUNT_DEACTIVATED':
                $subject = $this->subjectFor($report, $record->RAC_ACTION);
                $subject?->update([
                    'USR_STATUS' => $previous['USR_STATUS'] ?? 'ACTIVE',
                    'USR_TAKEDOWN_REASON' => null,
                    'USR_TAKEDOWN_AT' => null,
                    'USR_HIDDEN_BY_TAKEDOWN' => false,
                ]);
                break;

            case 'FARMER_LISTINGS_TAKEN_DOWN':
                foreach ($previous['listings'] ?? [] as $listingId => $status) {
                    Listing::where('LST_ID', $listingId)->update([
                        'LST_AVAILABILITY' => $status,
                        'LST_TAKEDOWN_REASON' => null,
                        'LST_TAKEDOWN_AT' => null,
                        'LST_HIDDEN_BY_TAKEDOWN' => false,
                        'LST_UPDATED_AT' => now(),
                    ]);
                }
                break;

            case 'MESSAGE_HIDDEN':
                Message::where('MSG_ID', $report->RPT_TARGET_ID)->update([
                    'MSG_VISIBILITY' => $previous['MSG_VISIBILITY'] ?? 'VISIBLE',
                    'MSG_HIDDEN_AT' => null,
                ]);
                break;
        }
    }

    /**
     * Reopen the reports a live action closed, so undoing a takedown puts the
     * complaints back in the queue as well as the subject back on the shelf.
     *
     * Only rows still sitting at Resolved are touched. If a moderator has since
     * set a report's status by hand, that later decision is the current one and
     * this leaves it alone; reopening it would silently undo a human's call.
     * The status each row had before the close is restored from the action
     * itself, so a report that was Reviewing does not come back as New and
     * pretend nobody had looked at it.
     *
     * The mass-report check runs again afterwards: reopening can put a target
     * back over the threshold, and a wave that was real when it was actioned is
     * real again once the action is undone. Skipping this would reopen the
     * reports but leave the target unflagged and invisible in the alerts view.
     */
    private function reopenClosedReports(ReportAction $record): void
    {
        $closed = $record->previous()['closed_reports'] ?? [];

        if ($closed === []) {
            return;
        }

        $reopened = [];

        foreach ($closed as $rptId => $status) {
            $changed = Report::where('RPT_ID', $rptId)
                ->where('RPT_STATUS', 'Resolved')
                ->update([
                    'RPT_STATUS' => $status ?: 'Reviewing',
                    'RPT_UPDATED_AT' => now(),
                ]);

            if ($changed) {
                $reopened[] = $rptId;
            }
        }

        if ($reopened === []) {
            return;
        }

        $massReport = app(MassReportService::class);
        Report::whereIn('RPT_ID', $reopened)->get()
            ->each(fn (Report $report) => $massReport->flagIfThresholdReached($report));
    }

    // ------------------------------------------------------------------ shared

    private function activeListingsFor(?Farmer $farmer)
    {
        if (! $farmer) {
            return collect();
        }

        return Listing::where('FMR_ID', $farmer->FMR_ID)
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->get();
    }

    private function pickOption(array $options, string $action): ?array
    {
        foreach ($options as $option) {
            if ($option['action'] === $action) {
                return $option;
            }
        }

        return null;
    }

    private function newActionId(): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (ReportAction::where('RAC_ID', $id)->exists());

        return $id;
    }

    /**
     * Tell a reporter whose report was closed as part of a cluster that it was
     * resolved, pointing at their own report.
     *
     * Separate from notifyReporter() because the wording is different: this
     * person's report was not the one the moderator acted on, it was closed by
     * the same decision. "We took action on your report" would claim a direct
     * judgement that did not happen.
     */
    private function notifyReportResolved(string $usrId, string $rptId): void
    {
        try {
            app(NotificationService::class)->notify(
                $usrId,
                'REPORT_UPDATE',
                'Your report was resolved',
                'We took action on something you reported. Thanks for flagging it.',
                $rptId,
            );
        } catch (\Throwable $e) {
            Log::warning('[notifications] sibling report notification failed', [
                'usr_id' => $usrId,
                'rpt_id' => $rptId,
                'message' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Tell the reporter what happened.
     *
     * Reporting used to be a one-way door: the buyer pressed submit and heard
     * nothing, so they could not tell whether a moderator looked at it or
     * whether reporting was simply broken. This used to go out through Laravel's
     * own database-channel notification, but that table cannot be de-duplicated
     * against and is served by a separate endpoint from the app's inbox. It now
     * writes a REPORT_UPDATE row to NOTIFICATION like every other notification,
     * so a reporter's updates and everything else land in one list.
     */
    private function notifyReporter(Report $report, ReportAction $record, bool $applied): void
    {
        $reporter = $report->user;

        if (! $reporter) {
            return;
        }

        // The action is already applied and recorded by the time this runs, so a
        // failure to notify must not surface as an error to the moderator: they
        // would see a failed request for work that genuinely succeeded, and be
        // tempted to apply the action again.
        try {
            app(NotificationService::class)->notify(
                $reporter->USR_ID,
                'REPORT_UPDATE',
                $applied ? 'We took action on your report' : 'A decision on your report was reversed',
                $applied
                    ? $record->label().'.'
                    : 'We undid '.$record->label().' after a second look.',
                // The report, not the listing: a message report has a listing id
                // only by accident, and the reporter wants to open the report.
                $report->RPT_ID,
            );
        } catch (\Throwable $e) {
            Log::warning('[notifications] report action notification failed', [
                'rpt_id' => $report->RPT_ID,
                'usr_id' => $reporter->USR_ID,
                'message' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Tell the reporter their report reached a decision.
     *
     * Only Resolved and Dismissed notify. Reviewing is the state a report passes
     * through while a moderator reads it, and a buyer who filed a report and was
     * told "we're reviewing it" has learned nothing they were not already
     * waiting to hear - while an admin moving a report into Reviewing to clear
     * the queue would otherwise generate a notification per report.
     *
     * A no-op change is not a change: the caller's compare-and-swap has already
     * established that the status genuinely moved, so there is nothing left to
     * re-test here.
     */
    private function notifyReporterOfStatus(Report $report, string $previousStatus, string $newStatus): void
    {
        if ($newStatus === $previousStatus) {
            return;
        }

        $copy = match ($newStatus) {
            'Resolved' => 'We resolved your report. Thanks for flagging it.',
            'Dismissed' => 'We reviewed your report and did not act on it.',
            default => null,
        };

        // null for New/Reviewing, which is the "do not notify" case.
        if ($copy === null) {
            return;
        }

        $reporter = $report->user;

        if (! $reporter) {
            return;
        }

        try {
            app(NotificationService::class)->notify(
                $reporter->USR_ID,
                'REPORT_UPDATE',
                $newStatus === 'Resolved' ? 'Your report was resolved' : 'Your report was dismissed',
                $copy,
                $report->RPT_ID,
            );
        } catch (\Throwable $e) {
            Log::warning('[notifications] report status notification failed', [
                'rpt_id' => $report->RPT_ID,
                'usr_id' => $reporter->USR_ID,
                'status' => $newStatus,
                'message' => $e->getMessage(),
            ]);
        }
    }

    private function findWithSubjects($id): Report
    {
        return Report::with(['listing', 'farmer.buyer.user', 'reportedUser', 'user'])
            ->where('RPT_ID', $id)
            ->firstOrFail();
    }
}
