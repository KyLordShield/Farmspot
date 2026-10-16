<?php

namespace App\Services;

use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\User;

/**
 * Shared moderation mechanics for reports and re-evaluations.
 *
 * Kept out of the controllers because the same two ideas are needed in more
 * than one place:
 *
 *   1. "move the open reports against this thing to a finished state". A
 *      takedown resolves the reports that prompted it, and an appeal decision
 *      either dismisses them (we were wrong) or resolves them (we were right).
 *      Doing it in one method means the queue and the appeals panel cannot
 *      disagree about which reports are finished.
 *
 *   2. "what reports are about this?". A target is a (type, id) pair, and one
 *      action can touch several: deactivating a farmer affects their account
 *      AND the farmer record, so reports against either are finished. Listing
 *      reports and person reports are still never merged into one count
 *      anywhere — this only enumerates them so they can be closed.
 *
 * Nothing here notifies anyone or writes an audit row; those are decisions the
 * caller makes, so a failure to notify never aborts a takedown that succeeded.
 */
class ModerationService
{
    /**
     * Move every open report against any of the given targets to $status, and
     * clear their mass-report flag. Returns how many rows changed.
     *
     * $targets is a list of [type, id] pairs. An empty list does nothing, which
     * is the correct outcome for an action with no reportable subject (hiding a
     * message, say). The flag is cleared here because a finished report should
     * not keep a target lit up in the queue — RPT_FLAGGED_AT comes back to null
     * so a genuinely new wave of reports can flag it again.
     */
    public function finishOpenReports(array $targets, string $status): int
    {
        if ($targets === []) {
            return 0;
        }

        return Report::query()
            ->where(function ($query) use ($targets) {
                foreach ($targets as [$type, $id]) {
                    $query->orWhere(function ($pair) use ($type, $id) {
                        $pair->where('RPT_TARGET_TYPE', $type)
                            ->where('RPT_TARGET_ID', $id);
                    });
                }
            })
            ->open()
            ->update([
                'RPT_STATUS' => $status,
                'RPT_UPDATED_AT' => now(),
                'RPT_FLAGGED_AT' => null,
            ]);
    }

    /**
     * The open reports against any of the given targets, newest first.
     *
     * A read-only companion to finishOpenReports(): a caller captures this
     * BEFORE the bulk close so it can tell the affected reporters what happened,
     * and so undo can reopen exactly the rows a decision finished. Each row
     * carries RPT_ID, USR_ID and RPT_STATUS.
     *
     * Deliberately not deduplicated. Callers that want one entry per person key
     * by USR_ID; the undo path wants every report id. Same query, two readings,
     * so there is no second place to get the target-matching logic wrong.
     */
    public function openReportsFor(array $targets): \Illuminate\Support\Collection
    {
        if ($targets === []) {
            return collect();
        }

        return Report::query()
            ->where(function ($query) use ($targets) {
                foreach ($targets as [$type, $id]) {
                    $query->orWhere(function ($pair) use ($type, $id) {
                        $pair->where('RPT_TARGET_TYPE', $type)
                            ->where('RPT_TARGET_ID', $id);
                    });
                }
            })
            ->open()
            ->orderByDesc('RPT_CREATED_AT')
            ->get(['RPT_ID', 'USR_ID', 'RPT_STATUS']);
    }

    /**
     * The targets a taken-down listing contributes.
     */
    public function targetsForListing(string $listingId): array
    {
        return [[Report::TARGET_LISTING, $listingId]];
    }

    /**
     * The targets a deactivated account contributes: the account itself, plus
     * the farmer record behind it if the person is also a seller.
     *
     * Without the farmer half, a report filed against a seller rather than
     * their account would stay open after the account it names was deactivated.
     */
    public function targetsForUser(User $user): array
    {
        $targets = [[Report::TARGET_USER, $user->USR_ID]];

        $farmerId = $user->buyer?->farmer?->FMR_ID;

        if ($farmerId) {
            $targets[] = [Report::TARGET_FARMER, $farmerId];
        }

        return $targets;
    }

    /**
     * The targets a farmer's taken-down catalogue contributes: the farmer
     * record, plus every listing that was actually taken down.
     */
    public function targetsForFarmer(Farmer $farmer, array $listingIds = []): array
    {
        $targets = [[Report::TARGET_FARMER, $farmer->FMR_ID]];

        foreach ($listingIds as $listingId) {
            $targets[] = [Report::TARGET_LISTING, $listingId];
        }

        return $targets;
    }

    /**
     * Put a listing back on sale and forget the takedown.
     *
     * ACTIVE, not "whatever it was before": an appeal approved by a human is a
     * verdict that the listing is allowed to trade, and the previous
     * availability was REMOVED anyway — that is the state being undone. The
     * reason and marker are cleared so the listing is no longer taken down and
     * a future takedown starts from a clean slate.
     */
    public function restoreListing(Listing $listing): void
    {
        $listing->forceFill([
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_TAKEDOWN_REASON' => null,
            'LST_TAKEDOWN_AT' => null,
            'LST_HIDDEN_BY_TAKEDOWN' => false,
            'LST_UPDATED_AT' => now(),
        ])->save();
    }

    /**
     * Reactivate an account and bring back only the listings the takedown hid.
     *
     * The LST_HIDDEN_BY_TAKEDOWN marker is the whole point: a farmer who had
     * already deleted some listings for their own reasons must not have those
     * resurrected when their account comes back. Only rows an admin removal put
     * into REMOVED are restored.
     */
    public function restoreAccount(User $user): void
    {
        $user->forceFill([
            'USR_STATUS' => 'ACTIVE',
            'USR_TAKEDOWN_REASON' => null,
            'USR_TAKEDOWN_AT' => null,
            'USR_HIDDEN_BY_TAKEDOWN' => false,
        ])->save();

        $farmerId = $user->buyer?->farmer?->FMR_ID;

        if (! $farmerId) {
            return;
        }

        Listing::where('FMR_ID', $farmerId)
            ->where('LST_HIDDEN_BY_TAKEDOWN', true)
            ->get()
            ->each(fn (Listing $listing) => $this->restoreListing($listing));
    }
}
