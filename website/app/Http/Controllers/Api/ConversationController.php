<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Controller;
use App\Models\Buyer;
use App\Models\Conversation;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Message;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ConversationController extends Controller
{
    use FormatsListings;

    /**
     * Start — or return the existing — conversation between the signed-in
     * buyer and the seller of a listing. Idempotent on purpose: the "Message
     * Seller" button calls this every time, and the unique key on
     * (LST_ID, BUY_ID) means a second thread can never be created.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'LST_ID' => ['required', 'string'],
        ]);

        $listing = Listing::find($validated['LST_ID']);

        if (! $listing) {
            return response()->json(['message' => 'Listing not found.'], 404);
        }

        $user = $request->user();
        $myBuyerId = $this->ensureBuyerId($user);
        $myFarmerId = $this->myFarmerId($user->USR_ID);

        // A seller has no reason to message their own crop.
        if ($myFarmerId && $myFarmerId === $listing->FMR_ID) {
            return response()->json([
                'message' => 'This is your own listing.',
            ], 422);
        }

        $withContext = ['listing.farm', 'listing.category', 'listing.farmer.buyer.user'];

        $existing = Conversation::where('LST_ID', $listing->LST_ID)
            ->where('BUY_ID', $myBuyerId)
            ->first();

        if ($existing) {
            return response()->json([
                'conversation' => $this->formatConversation(
                    $existing->load($withContext),
                    $myBuyerId
                ),
            ]);
        }

        do {
            $id = strtoupper(Str::random(6));
        } while (Conversation::where('CONV_ID', $id)->exists());

        $conversation = Conversation::create([
            'CONV_ID' => $id,
            'LST_ID' => $listing->LST_ID,
            'FRM_ID' => $listing->FRM_ID,
            'BUY_ID' => $myBuyerId,
            'FMR_ID' => $listing->FMR_ID,
            'CONV_CREATED_AT' => now(),
        ]);

        return response()->json([
            'conversation' => $this->formatConversation(
                $conversation->load($withContext),
                $myBuyerId
            ),
        ], 201);
    }

    /**
     * The signed-in user's inbox, newest activity first. A user who both buys
     * and sells sees both sets in one list, each row tagged with the role they
     * are playing in that thread.
     */
    public function index(Request $request)
    {
        $user = $request->user();
        $myBuyerId = $this->myBuyerId($user->USR_ID);
        $myFarmerId = $this->myFarmerId($user->USR_ID);

        // An account with neither a buyer nor a farmer row participates in no
        // conversation. Returning early is essential: an empty where() closure
        // below would compile to NO constraint and leak the whole inbox.
        if (! $myBuyerId && ! $myFarmerId) {
            return response()->json(['conversations' => []]);
        }

        $conversations = Conversation::with([
                'listing.farm',
                'listing.category',
                'listing.farmer.buyer.user',
            ])
            ->where(function ($query) use ($myBuyerId, $myFarmerId) {
                if ($myBuyerId) {
                    $query->where('BUY_ID', $myBuyerId);
                }
                if ($myFarmerId) {
                    $query->orWhere('FMR_ID', $myFarmerId);
                }
            })
            ->orderByDesc('CNV_LAST_MESSAGE_AT')
            ->orderByDesc('CONV_CREATED_AT')
            // Two threads can share a second; without a final tiebreak their
            // relative order would be arbitrary and the list could reshuffle
            // between two identical polls.
            ->orderByDesc('CONV_ID')
            ->get();

        // Unread counts for every thread in one grouped query, not one per row.
        $unread = Message::whereIn('CONV_ID', $conversations->pluck('CONV_ID'))
            ->where('USR_ID', '!=', $user->USR_ID)
            ->where('MSG_IS_READ', 0)
            ->selectRaw('CONV_ID, COUNT(*) as unread_count')
            ->groupBy('CONV_ID')
            ->pluck('unread_count', 'CONV_ID');

        return response()->json([
            'conversations' => $conversations->map(function ($conversation) use ($myBuyerId, $unread) {
                $data = $this->formatConversation($conversation, $myBuyerId);
                $data['unread_count'] = (int) ($unread[$conversation->CONV_ID] ?? 0);
                $data['my_role'] = $conversation->BUY_ID === $myBuyerId
                    ? 'BUYER'
                    : 'SELLER';

                return $data;
            })->values(),
        ]);
    }

    /**
     * Message history for one thread. The app polls this with
     * ?after=<MSG_ID> while the chat is open, so only messages newer than the
     * last one it holds come back. Opening the thread also clears the badge.
     */
    public function messages(Request $request, $id)
    {
        $conversation = $this->findAuthorized($request, $id);

        if ($conversation === 'missing') {
            return response()->json(['message' => 'Conversation not found.'], 404);
        }
        if ($conversation === 'forbidden') {
            return response()->json([
                'message' => 'This conversation is not yours.',
            ], 403);
        }

        $after = $request->query('after');

        // MSG_SEQ, not MSG_CREATED_AT, is the ordering key: it is monotonic, so
        // "newer than the last thing the app holds" is exact even when two
        // messages share a timestamp. The client still sends a message id,
        // which is resolved to its sequence here.
        $query = Message::where('CONV_ID', $conversation->CONV_ID)
            ->orderBy('MSG_SEQ');

        if ($after) {
            // The cursor is scoped to this thread on purpose: an id belonging to
            // some other conversation must be treated as unknown rather than
            // silently skewing this thread's window.
            $cursor = Message::where('CONV_ID', $conversation->CONV_ID)
                ->where('MSG_ID', $after)
                ->first();

            // A stale cursor (history trimmed, another device) must never blank
            // the thread, so an unknown id simply falls back to full history.
            if ($cursor) {
                $query->where('MSG_SEQ', '>', $cursor->MSG_SEQ);
            }
        }

        $messages = $query->get();

        // Reading the thread marks the other side's messages read, so the inbox
        // badge clears by simply opening the chat.
        Message::where('CONV_ID', $conversation->CONV_ID)
            ->where('USR_ID', '!=', $request->user()->USR_ID)
            ->where('MSG_IS_READ', 0)
            ->update(['MSG_IS_READ' => 1]);

        return response()->json([
            'messages' => $messages
                ->map(fn ($message) => $this->formatMessage($message, $request->user()->USR_ID))
                ->values(),
            'conversation' => $this->formatConversation(
                $conversation->load(['listing.farm', 'listing.category', 'listing.farmer.buyer.user']),
                $this->myBuyerId($request->user()->USR_ID)
            ),
        ]);
    }

    /**
     * Post a message into a thread. Sending and reading share one authorization
     * rule — you may only touch a thread you are a participant of — so it is
     * resolved once, here, for both.
     */
    public function sendMessage(Request $request, $id)
    {
        $conversation = $this->findAuthorized($request, $id);

        if ($conversation === 'missing') {
            return response()->json(['message' => 'Conversation not found.'], 404);
        }
        if ($conversation === 'forbidden') {
            return response()->json([
                'message' => 'This conversation is not yours.',
            ], 403);
        }

        $validated = $request->validate([
            'content' => ['required', 'string', 'max:1000'],
        ]);

        // 'required' alone still admits a whitespace-only string.
        if (trim($validated['content']) === '') {
            return response()->json([
                'message' => 'Message cannot be empty.',
                'errors' => ['content' => ['Message cannot be empty.']],
            ], 422);
        }

        $user = $request->user();

        $message = DB::transaction(function () use ($conversation, $validated, $user) {
            do {
                $messageId = strtoupper(Str::random(6));
            } while (Message::where('MSG_ID', $messageId)->exists());

            $message = Message::create([
                'MSG_ID' => $messageId,
                'CONV_ID' => $conversation->CONV_ID,
                'USR_ID' => $user->USR_ID,
                'MSG_CONTENT' => trim($validated['content']),
                // A message row has exactly one recipient, so MSG_IS_READ means
                // "the other side has read it" — it must start at 0. The sender
                // never counts their own messages toward their badge anyway
                // (the unread query filters USR_ID != the viewer), so leaving
                // it unread is what makes the recipient's badge light up.
                'MSG_IS_READ' => 0,
                'MSG_CREATED_AT' => now(),
            ]);

            // Keep the denormalized inbox preview in step with the thread.
            Conversation::where('CONV_ID', $conversation->CONV_ID)->update([
                'CNV_LAST_MESSAGE' => mb_substr($message->MSG_CONTENT, 0, 500),
                'CNV_LAST_MESSAGE_AT' => $message->MSG_CREATED_AT,
            ]);

            return $message;
        });

        return response()->json([
            'message' => $this->formatMessage($message, $user->USR_ID),
        ], 201);
    }

    /**
     * Load a conversation and confirm the signed-in user is one of the two
     * participants — either the buyer who started the thread, or the seller
     * whose farmer record owns the listing. Returns 'missing' / 'forbidden'
     * sentinels so each caller chooses its own status code.
     */
    private function findAuthorized(Request $request, $id)
    {
        $conversation = Conversation::find($id);

        if (! $conversation) {
            return 'missing';
        }

        $user = $request->user();

        if ($conversation->BUY_ID === $this->myBuyerId($user->USR_ID)) {
            return $conversation;
        }

        $myFarmerId = $this->myFarmerId($user->USR_ID);
        if ($myFarmerId && $conversation->FMR_ID === $myFarmerId) {
            return $conversation;
        }

        return 'forbidden';
    }

    /** The caller's own BUY_ID, or null for an account with no buyer row. */
    private function myBuyerId($userId): ?string
    {
        return Buyer::where('USR_ID', $userId)->value('BUY_ID');
    }

    /**
     * The caller's own BUY_ID, creating the row if it is missing.
     *
     * A buyer row is not created at registration — it is created lazily the
     * first time something needs one (see SellerController@activate), and
     * conversation.BUY_ID is a foreign key to buyer.BUY_ID. So a pure buyer
     * who registered and never turned on seller mode would have no BUY_ID to
     * start a thread with. This mirrors the activate() pattern exactly rather
     * than changing the registration flow.
     */
    private function ensureBuyerId($user): string
    {
        $buyer = $user->buyer()->first();

        if (! $buyer) {
            do {
                $buyId = strtoupper(Str::random(6));
            } while (Buyer::where('BUY_ID', $buyId)->exists());

            $buyer = Buyer::create([
                'BUY_ID' => $buyId,
                'USR_ID' => $user->USR_ID,
            ]);
        }

        return $buyer->BUY_ID;
    }

    /** The caller's own FMR_ID, or null for a buyer-only account. */
    private function myFarmerId($userId): ?string
    {
        $buyerId = $this->myBuyerId($userId);

        return $buyerId ? Farmer::where('BUY_ID', $buyerId)->value('FMR_ID') : null;
    }

    /**
     * A message plus the one derived field the app needs: whether it is mine.
     * Comparing the sender against the caller's own USR_ID means the identical
     * payload renders correctly for the buyer and the seller, with no role
     * column anywhere in the schema.
     */
    private function formatMessage(Message $message, $viewerId): array
    {
        return [
            'id' => $message->MSG_ID,
            'conversation_id' => $message->CONV_ID,
            'sender_id' => $message->USR_ID,
            'is_mine' => $message->USR_ID === $viewerId,
            'content' => $message->MSG_CONTENT,
            'is_read' => (bool) $message->MSG_IS_READ,
            'created_at' => $message->MSG_CREATED_AT,
        ];
    }

    /**
     * A conversation plus the context the inbox row and chat header need: what
     * it is about (the listing), who it is with (farm + the other party), and
     * the last message. The listing is embedded through the shared
     * FormatsListings contract so a chat header shows exactly the same crop and
     * farm names as the feed does.
     */
    private function formatConversation(Conversation $conversation, ?string $viewerBuyerId): array
    {
        $listing = $conversation->listing;
        $viewerIsBuyer = $viewerBuyerId !== null
            && $conversation->BUY_ID === $viewerBuyerId;

        // Whoever is on the other side: the seller when the viewer is the
        // buyer, otherwise the buyer who started the thread. conversation.BUY_ID
        // is a buyer.BUY_ID, so the buyer's user is one hop along its own
        // relation rather than a hand-written join.
        $otherUser = $viewerIsBuyer
            ? $listing?->farmer?->buyer?->user
            : Buyer::with('user')->find($conversation->BUY_ID)?->user;

        return [
            'id' => $conversation->CONV_ID,
            'listing_id' => $conversation->LST_ID,
            'buyer_id' => $conversation->BUY_ID,
            'seller_farmer_id' => $conversation->FMR_ID,
            'farm_id' => $conversation->FRM_ID,
            'last_message' => $conversation->CNV_LAST_MESSAGE,
            'last_message_at' => $conversation->CNV_LAST_MESSAGE_AT,
            'created_at' => $conversation->CONV_CREATED_AT,
            'listing' => $listing ? $this->formatListing($listing) : null,
            'farm' => [
                'id' => $listing?->farm?->FRM_ID ?? $conversation->FRM_ID,
                'name' => $listing?->farm?->FRM_NAME ?? null,
                'barangay' => $listing?->farm?->FRM_BARANGAY ?? null,
            ],
            'other_party' => [
                'id' => $otherUser?->USR_ID,
                'name' => $otherUser?->USR_NAME,
                'photo' => $otherUser?->USR_PHOTO_PATH,
            ],
        ];
    }
}
