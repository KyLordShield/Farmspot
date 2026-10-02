<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Buyer;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Report;
use App\Models\User;
use Illuminate\Http\Request;

/**
 * Report a listing, a chat message, a farmer/seller, or another user.
 *
 * The reporter is always derived from the bearer token, never from the request
 * body. A report is an accusation against another person, so the three rules
 * that matter most are all about who is allowed to make one:
 *
 *   1. You cannot report yourself or your own content.
 *   2. You can only report a message you actually received. Not just a
 *      conversation you are in, but the message that was sent TO you, so a
 *      sender cannot file a report against their own message to get themselves
 *      flagged.
 *   3. The target must exist. Verified per type rather than by a generic
 *      exists: rule, because a missing target and a target that exists but
 *      belongs to someone else are different answers, and only the second
 *      should say so.
 *
 * Nothing is hidden or suspended automatically. Reports land in the admin
 * queue and a moderator decides, because a threshold-based auto-hide lets a
 * group of users take a competitor's crop off sale by tapping report.
 */
class ReportController extends Controller
{
    /**
     * File a report.
     *
     * 201 with the new report, 200 when an identical report from the same
     * person about the same thing already exists. The 200 is not an
     * afterthought: the app retries a submit when the network drops mid-flight
     * and a buyer must not end up with the same complaint in the queue three
     * times because their connection was bad.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'target_type' => ['required', 'in:'.implode(',', Report::TARGET_TYPES)],
            'target_id' => ['required', 'string', 'size:6'],
            'reason' => ['required', 'in:'.implode(',', array_keys(Report::REASONS))],
            'details' => ['nullable', 'string', 'max:1000'],
        ]);

        // 'required' admits a whitespace-only string, which would be a report
        // with no subject. Same guard the message endpoint uses.
        if (trim($validated['target_id']) === '') {
            return response()->json([
                'message' => 'The report is missing a target.',
            ], 422);
        }

        $user = $request->user();
        $type = $validated['target_type'];
        $targetId = $validated['target_id'];
        $reason = $validated['reason'];
        $details = isset($validated['details']) && trim($validated['details']) !== ''
            ? $validated['details']
            : null;

        // The listing the report is filed against, for context. Only a listing
        // report requires one; a message report inherits its thread's listing,
        // and a person has no listing at all.
        $listingId = null;
        $subject = $this->resolveTarget($user, $type, $targetId);

        if ($subject === 'missing') {
            return response()->json([
                'message' => 'That thing could not be found.',
            ], 404);
        }

        if ($subject === 'forbidden') {
            return response()->json([
                'message' => $this->forbiddenMessage($type),
            ], 403);
        }

        if ($subject['listing_id'] ?? null) {
            $listingId = $subject['listing_id'];
        }

        $existing = $this->recentDuplicate($user->USR_ID, $type, $targetId, $reason);
        if ($existing) {
            return response()->json([
                'message' => 'You have already reported this. Our team is reviewing it.',
                'report' => $this->format($existing),
            ], 200);
        }

        $report = Report::create([
            // The model assigns this, not the database. RPT_ID used to be
            // AUTO_INCREMENT, which made it the one id in this API that arrived
            // as a JSON number and crashed the app's `as String` cast.
            'RPT_ID' => Report::newId(),
            'LST_ID' => $listingId,
            'USR_ID' => $user->USR_ID,
            'RPT_REASON' => Report::REASONS[$reason],
            'RPT_REASON_CODE' => $reason,
            'RPT_DETAILS' => $details,
            'RPT_TARGET_TYPE' => $type,
            'RPT_TARGET_ID' => $targetId,
        ]);

        // RPT_STATUS and RPT_CREATED_AT are filled by column defaults, which
        // MySQL applies but never hands back to the inserting connection. Without
        // this the response would claim status null / created_at null for a row
        // that is in fact "New" and timestamped, and would disagree with the
        // duplicate branch below, which formats a model that was read back.
        $report->refresh();

        return response()->json([
            'message' => 'Thanks. Our team will review this.',
            'report' => $this->format($report),
        ], 201);
    }

    /**
     * Confirm the target exists and that this person is allowed to report it.
     *
     * Returns 'missing' / 'forbidden' sentinels, or an array carrying the
     * subject and the listing context. The sentinel style is borrowed from
     * ConversationController::findAuthorized so the two read the same way.
     */
    private function resolveTarget(User $user, string $type, string $targetId)
    {
        return match ($type) {
            Report::TARGET_LISTING => $this->resolveListing($user, $targetId),
            Report::TARGET_MESSAGE => $this->resolveMessage($user, $targetId),
            Report::TARGET_FARMER => $this->resolveFarmer($user, $targetId),
            Report::TARGET_USER => $this->resolveUser($user, $targetId),
            default => 'missing',
        };
    }

    private function resolveListing(User $user, string $listingId)
    {
        $listing = Listing::find($listingId);

        if (! $listing) {
            return 'missing';
        }

        // Reporting your own crop is never a moderation signal. The listing is
        // owned through the farmer, and the farmer is owned through a buyer
        // row, so the walk is buyer -> farmer -> user.
        if ($this->farmerOwnerId($listing->FMR_ID) === $user->USR_ID) {
            return 'forbidden';
        }

        return ['listing_id' => $listing->LST_ID];
    }

    /**
     * A message may only be reported by the person it was sent to.
     *
     * A non-participant gets 'missing' rather than 'forbidden' on purpose:
     * anyone can put a plausible MSG_ID in a request, and a 403 would confirm
     * the message exists. A 404 leaks nothing.
     */
    private function resolveMessage(User $user, string $messageId)
    {
        $message = Message::with('conversation')->find($messageId);

        if (! $message) {
            return 'missing';
        }

        $conversation = $message->conversation;

        if (! $conversation || ! $this->isParticipant($user, $conversation)) {
            return 'missing';
        }

        // The sender cannot report their own message.
        if ($message->USR_ID === $user->USR_ID) {
            return 'forbidden';
        }

        // A thread's listing is real context for whoever reads the queue: it
        // separates "abusive message about a live sale" from "unwanted contact
        // about a listing the buyer had already dismissed".
        return ['listing_id' => $conversation->LST_ID];
    }

    private function resolveFarmer(User $user, string $farmerId)
    {
        $farmer = Farmer::find($farmerId);

        if (! $farmer) {
            return 'missing';
        }

        if ($farmer->BUY_ID && $this->buyerOwnerId($farmer->BUY_ID) === $user->USR_ID) {
            return 'forbidden';
        }

        return [];
    }

    private function resolveUser(User $user, string $targetUserId)
    {
        $target = User::find($targetUserId);

        if (! $target) {
            return 'missing';
        }

        if ($target->USR_ID === $user->USR_ID) {
            return 'forbidden';
        }

        return [];
    }

    /**
     * Whether the user is one of the thread's two participants.
     *
     * Same rule as reading a conversation: the buyer who started it, or the
     * seller whose farmer record owns it.
     */
    private function isParticipant(User $user, $conversation): bool
    {
        $buyerId = $user->buyer?->BUY_ID;
        if ($buyerId && $conversation->BUY_ID === $buyerId) {
            return true;
        }

        $farmerId = $user->buyer?->farmer?->FMR_ID;

        return $farmerId !== null && $conversation->FMR_ID === $farmerId;
    }

    /**
     * The user id behind a farmer record, or null if the chain is unlinked.
     *
     * A farmer is reachable from a user through buyer, so this is the walk
     * every self-report guard needs. Written as one joined query rather than
     * two round trips, since it runs on the hot path of every report.
     */
    private function farmerOwnerId(?string $farmerId): ?string
    {
        if (! $farmerId) {
            return null;
        }

        return Farmer::join('buyer', 'buyer.BUY_ID', '=', 'farmer.BUY_ID')
            ->where('farmer.FMR_ID', $farmerId)
            ->value('buyer.USR_ID');
    }

    private function buyerOwnerId(?string $buyerId): ?string
    {
        return $buyerId ? Buyer::where('BUY_ID', $buyerId)->value('USR_ID') : null;
    }

    /**
     * An identical report from the same person in the last day.
     *
     * A day, not forever: a buyer who is still being harassed tomorrow should
     * be able to say so again, and the moderator can see the repeat.
     */
    private function recentDuplicate(string $reporterId, string $type, string $targetId, string $reason): ?Report
    {
        return Report::where('USR_ID', $reporterId)
            ->where('RPT_TARGET_TYPE', $type)
            ->where('RPT_TARGET_ID', $targetId)
            ->where('RPT_REASON_CODE', $reason)
            ->where('RPT_CREATED_AT', '>=', now()->subDay())
            // By creation time, not by id. RPT_ID used to be AUTO_INCREMENT, so
            // latest('RPT_ID') genuinely meant the newest row; it is now six
            // random digits, and sorting those compares them as strings. A buyer
            // who filed the same complaint twice in a day would be handed back
            // whichever of their reports sorts highest rather than the one they
            // actually just sent, with its id and created_at to match.
            ->latest('RPT_CREATED_AT')
            ->first();
    }

    private function forbiddenMessage(string $type): string
    {
        return match ($type) {
            Report::TARGET_LISTING => 'This is your own listing.',
            Report::TARGET_MESSAGE => 'You can only report a message that was sent to you.',
            Report::TARGET_FARMER => 'This is your own seller account.',
            default => 'This is your own account.',
        };
    }

    private function format(Report $report): array
    {
        return [
            // A 6-character id like every other id in this API, so a client
            // never has to know which kind of number it received.
            'id' => $report->RPT_ID,
            'target_type' => $report->RPT_TARGET_TYPE,
            'target_id' => $report->RPT_TARGET_ID,
            'reason' => $report->RPT_REASON_CODE,
            'reason_label' => $report->reasonLabel(),
            'details' => $report->RPT_DETAILS,
            'status' => $report->RPT_STATUS,
            'created_at' => $report->RPT_CREATED_AT,
        ];
    }
}
