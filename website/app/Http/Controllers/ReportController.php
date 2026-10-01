<?php

namespace App\Http\Controllers;

use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Report;
use App\Models\ReportAction;
use App\Models\User;
use App\Notifications\ReportActioned;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ReportController extends Controller
{
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

        return view('reports', [
            'reports' => $reports,
            'counts' => $counts,
            'typeCounts' => $typeCounts,
            'actionLabels' => Report::ACTION_LABELS,
        ]);
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

        $option = $this->pickOption($this->availableActions($report), $action);
        if ($option === null) {
            return redirect()->route('reports.show', $report->RPT_ID)
                ->with('error', $this->blockedReasons($report)[0]
                    ?? "That action is not available on report #{$report->RPT_ID}.");
        }

        $validated = $request->validate([
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        $previous = $this->apply($report, $action);

        $record = ReportAction::create([
            'RAC_ID' => $this->newActionId(),
            'RPT_ID' => $report->RPT_ID,
            'RAC_ACTION' => $action,
            'RAC_SUBJECT_TYPE' => Report::ENFORCEMENT[$report->RPT_TARGET_TYPE][$action]['subject'],
            'RAC_SUBJECT_ID' => $report->RPT_TARGET_ID,
            'RAC_PREV' => json_encode($previous),
            'RAC_NOTE' => $validated['note'] ?? null,
            'RAC_BY' => $request->user()->USR_ID,
            'RAC_APPLIED_AT' => now(),
        ]);

        // Taking something down is work in progress, so a report still sitting
        // unread as New moves along. A moderator who already set a status keeps
        // it.
        if ($report->RPT_STATUS === 'New') {
            $report->update(['RPT_STATUS' => 'Reviewing', 'RPT_UPDATED_AT' => now()]);
        }

        $this->notifyReporter($report, $record, applied: true);

        return redirect()->route('reports.show', $report->RPT_ID)
            ->with('success', $option['done']);
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

        $report->update([
            'RPT_STATUS' => $validated['status'],
            // Stamped so the queue can show how long a report has been open.
            // The table predates Eloquent timestamps, so this is set by hand.
            'RPT_UPDATED_AT' => now(),
        ]);

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

    // ------------------------------------------------------------------ apply

    /**
     * Make the change and return what has to be put back to undo it.
     */
    private function apply(Report $report, string $action): array
    {
        $subject = $this->subjectFor($report, $action);

        return match ($action) {
            'LISTING_TAKEN_DOWN' => $this->takeDownListings(
                Listing::where('LST_ID', $subject->LST_ID)
            ),
            'SELLER_DEACTIVATED' => $this->deactivateAccount($subject),
            'FARMER_ACCOUNT_DEACTIVATED' => $this->deactivateAccount($subject),
            'FARMER_LISTINGS_TAKEN_DOWN' => $this->takeDownListings($this->activeListingsFor($report->farmer)),
            'ACCOUNT_DEACTIVATED' => $this->deactivateAccount($subject),
            'MESSAGE_HIDDEN' => $this->hideMessage($subject),
            default => [],
        };
    }

    /**
     * Off sale, reversibly.
     *
     * REMOVED is the same soft state the seller's own delete-listing action uses,
     * and it is what every buyer-facing query filters on, so this genuinely
     * removes it from the app rather than just flagging it.
     */
    private function takeDownListings($listings): array
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
     */
    private function deactivateAccount(User $user): array
    {
        $previous = ['USR_STATUS' => $user->USR_STATUS];

        $user->update(['USR_STATUS' => 'DEACTIVATED']);
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
                    'LST_UPDATED_AT' => now(),
                ]);
                break;

            case 'SELLER_DEACTIVATED':
            case 'FARMER_ACCOUNT_DEACTIVATED':
            case 'ACCOUNT_DEACTIVATED':
                $subject = $this->subjectFor($report, $record->RAC_ACTION);
                $subject?->update(['USR_STATUS' => $previous['USR_STATUS'] ?? 'ACTIVE']);
                break;

            case 'FARMER_LISTINGS_TAKEN_DOWN':
                foreach ($previous['listings'] ?? [] as $listingId => $status) {
                    Listing::where('LST_ID', $listingId)->update([
                        'LST_AVAILABILITY' => $status,
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
     * Tell the reporter what happened.
     *
     * Reporting used to be a one-way door: the buyer pressed submit and heard
     * nothing, so they could not tell whether a moderator looked at it or
     * whether reporting was simply broken. The app has no inbox screen yet, but
     * the record exists and is readable, which makes the screen a rendering job
     * rather than a data-modelling one.
     */
    private function notifyReporter(Report $report, ReportAction $record, bool $applied): void
    {
        $report->user?->notify(new ReportActioned($report, $record, $applied));
    }

    private function findWithSubjects($id): Report
    {
        return Report::with(['listing', 'farmer.buyer.user', 'reportedUser', 'user'])
            ->where('RPT_ID', $id)
            ->firstOrFail();
    }
}
