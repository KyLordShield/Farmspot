<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\UserNotification;
use Illuminate\Http\Request;

/**
 * The signed-in user's notification inbox.
 *
 * Four endpoints, and the only ones that read or write NOTIFICATION.
 *
 * The scope rule is the important part: every query is rooted at
 * $request->user()->USR_ID and nothing else. A notification id is a guessable
 * six-character string, so "look this one up and then check the owner" would
 * answer 403 for someone else's row — confirming it exists. Scoping the query
 * itself makes every other user's notification simply not found, which is what
 * a non-existent id returns anyway.
 */
class NotificationController extends Controller
{
    /**
     * The inbox, newest first.
     *
     * Paginated at 20 rather than returning everything: a seller on a weak
     * connection should not download a year of history to render the top of the
     * list, and the client can page.
     *
     * NOTIF_ID is the final tiebreak. NOTIF_CREATED_AT is a datetime with
     * second resolution and several notifications can be written inside the
     * same second — the expiry command loops over listings — so without a
     * tiebreak the order of those rows would be arbitrary and the list could
     * reshuffle between two identical pulls.
     */
    public function index(Request $request)
    {
        $notifications = UserNotification::where('USR_ID', $request->user()->USR_ID)
            ->orderByDesc('NOTIF_CREATED_AT')
            ->orderByDesc('NOTIF_ID')
            ->paginate(20);

        return response()->json([
            'notifications' => collect($notifications->items())
                ->map(fn (UserNotification $notification) => $this->format($notification))
                ->values(),
            'unread_count' => UserNotification::where('USR_ID', $request->user()->USR_ID)
                ->where('NOTIF_IS_READ', 0)
                ->count(),
            // Echoed so the client can drive its page buttons without having to
            // hardcode the page size.
            'current_page' => $notifications->currentPage(),
            'last_page' => $notifications->lastPage(),
            'per_page' => $notifications->perPage(),
            'total' => $notifications->total(),
        ]);
    }

    /**
     * Just the badge number.
     *
     * Separate from the list because the home screen needs this on every open
     * and on every pull-to-refresh, and should not have to download 20 rows of
     * text to learn whether there is anything to show.
     */
    public function unreadCount(Request $request)
    {
        return response()->json([
            'count' => UserNotification::where('USR_ID', $request->user()->USR_ID)
                ->where('NOTIF_IS_READ', 0)
                ->count(),
        ]);
    }

    /**
     * Mark one notification read.
     *
     * Scoped to the owner rather than fetched-then-checked, so someone else's
     * id is indistinguishable from one that never existed. Re-marking something
     * already read is not an error: the app marks read the moment a row is
     * opened, and a retry over a dropped connection should not surface a
     * failure the user cannot act on.
     */
    public function markAsRead(Request $request, $id)
    {
        $notification = UserNotification::where('NOTIF_ID', $id)
            ->where('USR_ID', $request->user()->USR_ID)
            ->first();

        if (! $notification) {
            return response()->json(['message' => 'Notification not found.'], 404);
        }

        $notification->NOTIF_IS_READ = 1;
        $notification->save();

        return response()->json([
            'message' => 'Notification marked as read.',
            'notification' => $this->format($notification->refresh()),
        ]);
    }

    /**
     * Mark everything read.
     *
     * A single UPDATE rather than a loop of per-row writes — a user with a few
     * hundred notifications should not cause a few hundred queries, and the
     * phone that is behind to clear the badge is exactly the phone on the
     * slowest connection.
     *
     * Returns the number changed rather than the unread count afterwards, since
     * that is the number the client can reconcile against what it displayed.
     */
    public function markAllAsRead(Request $request)
    {
        $marked = UserNotification::where('USR_ID', $request->user()->USR_ID)
            ->where('NOTIF_IS_READ', 0)
            ->update(['NOTIF_IS_READ' => 1]);

        return response()->json([
            'message' => 'Notifications marked as read.',
            'marked_read' => $marked,
            'count' => 0,
        ]);
    }

    /**
     * One row as the app needs it.
     *
     * Keys are lower snake_case, matching every other endpoint in this API, and
     * NOTIF_IS_READ is a real bool so the Dart client can use it directly
     * rather than comparing against 0. ref_id is what the app deep-links on;
     * it is null for notifications with nothing to open.
     */
    private function format(UserNotification $notification): array
    {
        return [
            'id' => $notification->NOTIF_ID,
            'type' => $notification->NOTIF_TYPE,
            'title' => $notification->NOTIF_TITLE,
            'body' => $notification->NOTIF_BODY,
            'ref_id' => $notification->NOTIF_REF_ID,
            'is_read' => (bool) $notification->NOTIF_IS_READ,
            'created_at' => $notification->NOTIF_CREATED_AT,
        ];
    }
}