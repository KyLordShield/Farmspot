<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Controller;
use App\Models\Buyer;
use App\Models\BuyRequest;
use App\Support\BuyRequestAccess;
use App\Models\Conversation;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Message;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class ConversationController extends Controller
{
    use FormatsListings;

    public function storeForBuyRequest(Request $request, string $id)
    {
        $seller = BuyRequestAccess::seller($request->user());
        [$conversation, $created] = DB::transaction(function () use ($id, $request, $seller) {
            $buyRequest = BuyRequest::whereKey($id)->lockForUpdate()->firstOrFail();
            abort_if($buyRequest->BRQ_REMOVED_AT !== null, 404, 'This request has been removed.');
            abort_if($buyRequest->USR_ID === $request->user()->USR_ID, 422, 'You cannot contact your own request.');
            $owner = User::whereKey($buyRequest->USR_ID)->lockForUpdate()->firstOrFail();
            abort_unless($owner->USR_STATUS === 'ACTIVE', 403, 'This buyer is no longer active.');
            $existing = Conversation::where('BRQ_ID', $id)->where('FMR_ID', $seller->FMR_ID)->first();
            if ($existing) return [$existing, false];
            do { $conversationId = strtoupper(Str::random(6)); } while (Conversation::whereKey($conversationId)->exists());
            return [Conversation::create([
                'CONV_ID' => $conversationId, 'BRQ_ID' => $id,
                'BUY_ID' => $this->ensureBuyerId($owner), 'FMR_ID' => $seller->FMR_ID,
                'FRM_ID' => $seller->farms->sortBy('FRM_ID')->first()->FRM_ID,
                'CONV_CREATED_AT' => now(),
            ]), true];
        });
        return response()->json(['conversation' => $this->formatConversation($conversation->load(['buyRequest', 'farmer.buyer.user', 'farm']), $this->myBuyerId($request->user()->USR_ID))], $created ? 201 : 200);
    }

    public function requestResponses(Request $request, string $id)
    {
        $row = BuyRequest::findOrFail($id);
        abort_unless($row->USR_ID === $request->user()->USR_ID, 403, 'This request is not yours.');
        $rows = Conversation::with(['buyRequest', 'farmer.buyer.user', 'farm'])
            ->where('BRQ_ID', $id)->orderByDesc('CNV_LAST_MESSAGE_AT')->orderByDesc('CONV_CREATED_AT')->get();
        return response()->json(['conversations' => $rows->map(fn ($c) => $this->formatConversation($c, $c->BUY_ID))->values()]);
    }

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

        $withContext = ['listing.farm', 'listing.category', 'listing.farmer.buyer.user', 'buyRequest', 'farmer.buyer.user', 'farm'];

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
                'buyRequest', 'farmer.buyer.user', 'farm',
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
            ->visible()
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
            ->visible()
            ->orderBy('MSG_SEQ');

        if ($after) {
            // The cursor is scoped to this thread on purpose: an id belonging to
            // some other conversation must be treated as unknown rather than
            // silently skewing this thread's window.
            $cursor = Message::where('CONV_ID', $conversation->CONV_ID)
                ->visible()
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
        // Marked read here, but only what the reader can actually see: a hidden
        // message is gone from the thread, so it must not clear the badge
        // either.
        Message::where('CONV_ID', $conversation->CONV_ID)
            ->visible()
            ->where('USR_ID', '!=', $request->user()->USR_ID)
            ->where('MSG_IS_READ', 0)
            ->update(['MSG_IS_READ' => 1]);

        return response()->json([
            'messages' => $messages
                ->map(fn ($message) => $this->formatMessage($message, $request->user()->USR_ID))
                ->values(),
            'conversation' => $this->formatConversation(
                $conversation->load(['listing.farm', 'listing.category', 'listing.farmer.buyer.user', 'buyRequest', 'farmer.buyer.user', 'farm']),
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

        // Check if the other party in the conversation is still active.
        // If they have been deactivated or blocked, prevent sending new messages
        // and inform the sender clearly.
        $otherUser = $this->getOtherPartyUser($conversation, $request->user());
        if ($otherUser && $otherUser->USR_STATUS !== 'ACTIVE') {
            $status = $otherUser->USR_STATUS;
            $message = $status === 'DEACTIVATED'
                ? 'This user has been deactivated and can no longer receive messages.'
                : 'This user is no longer active and can no longer receive messages.';
            return response()->json(['message' => $message], 403);
        }

        $validated = $request->validate([
            'content' => ['nullable', 'string', 'max:1000'],
            'photo' => ['nullable', 'image', 'max:5120'],
            // A location is a pair: one coordinate without the other cannot be
            // plotted, so each is required when its partner is present.
            'latitude' => ['nullable', 'numeric', 'between:-90,90', 'required_with:longitude'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180', 'required_with:latitude'],
            'location_label' => ['nullable', 'string', 'max:255'],
            // Sellers share a farm, not a device fix. The server looks the
            // coordinates up itself so the pin always matches the farm the
            // recipient is navigating to, even if the phone's GPS drifts.
            'farm_id' => ['nullable', 'string', 'size:6'],
        ]);

        $content = trim($validated['content'] ?? '');
        $photo = $request->file('photo');

        $farmId = $validated['farm_id'] ?? null;
        $latitude = isset($validated['latitude'])
            ? (float) $validated['latitude']
            : null;
        $longitude = isset($validated['longitude'])
            ? (float) $validated['longitude']
            : null;
        $hasLocation = $latitude !== null && $longitude !== null;
        $locationLabel = trim((string) ($validated['location_label'] ?? ''));
        $locationLabel = $locationLabel === ''
            ? null
            : mb_substr($locationLabel, 0, 255);

        if ($farmId !== null) {
            $farm = Farm::find($farmId);
            $farmerId = $request->user()->buyer?->farmer?->FMR_ID;

            // A seller may only share one of their own farms. Without this a
            // crafted request could pin somebody else's land onto a message.
            if (! $farm || ! $farmerId || $farm->FMR_ID !== $farmerId) {
                return response()->json([
                    'message' => 'You can only share one of your own farms.',
                    'errors' => ['farm_id' => ['You can only share one of your own farms.']],
                ], 422);
            }

            if ($farm->FRM_LATITUDE === null || $farm->FRM_LONGITUDE === null) {
                return response()->json([
                    'message' => 'This farm has no map location yet.',
                    'errors' => ['farm_id' => ['This farm has no map location yet.']],
                ], 422);
            }

            $latitude = (float) $farm->FRM_LATITUDE;
            $longitude = (float) $farm->FRM_LONGITUDE;
            $hasLocation = true;

            // The farm's own name is the useful label; a caller can still
            // override it with something like "Farm gate".
            $locationLabel ??= mb_substr((string) $farm->FRM_NAME, 0, 255);
        }

        // A message needs something to say: text, a photo, or a pin. 'nullable'
        // alone would admit a request with none of them.
        if ($content === '' && ! $photo && ! $hasLocation) {
            return response()->json([
                'message' => 'Message cannot be empty.',
                'errors' => ['content' => ['Message cannot be empty.']],
            ], 422);
        }

        $user = $request->user();

        // Upload before touching the database, so a failed upload leaves no
        // empty message row behind. Odd but honest: the previews say "Photo",
        // because a photo in the app cannot be rendered as text.
        $imageUrl = null;
        if ($photo) {
            $extension = $photo->getClientOriginalExtension() ?: 'jpg';
            $path = "message-images/{$conversation->CONV_ID}/" . uniqid() . ".{$extension}";
            Storage::disk('cloudinary')->put($path, $photo->getRealPath());
            $imageUrl = Storage::disk('cloudinary')->url($path);
        }

        $message = DB::transaction(function () use ($conversation, $content, $imageUrl, $user, $hasLocation, $latitude, $longitude, $locationLabel, $farmId) {
            do {
                $messageId = strtoupper(Str::random(6));
            } while (Message::where('MSG_ID', $messageId)->exists());

            $message = Message::create([
                'MSG_ID' => $messageId,
                'CONV_ID' => $conversation->CONV_ID,
                'USR_ID' => $user->USR_ID,
                // An image-only message keeps its text column as the empty
                // string the old validation would have rejected, but the photo
                // URL is what makes it a real message. A pin-only message is
                // the same shape, with the coordinates instead of the URL.
                'MSG_CONTENT' => $content,
                'MSG_IMAGE_PATH' => $imageUrl,
                'MSG_LATITUDE' => $hasLocation ? $latitude : null,
                'MSG_LONGITUDE' => $hasLocation ? $longitude : null,
                'MSG_LOCATION_LABEL' => $locationLabel,
                'MSG_FARM_ID' => $farmId,
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
                'CNV_LAST_MESSAGE' => $this->previewFor(
                    $imageUrl,
                    $content,
                    $hasLocation,
                    $locationLabel
                ),
                'CNV_LAST_MESSAGE_AT' => $message->MSG_CREATED_AT,
            ]);

            return $message;
        });

        return response()->json([
            'message' => $this->formatMessage($message, $user->USR_ID),
        ], 201);
    }

    /**
     * Get the other party user in the conversation (the person the viewer is chatting with).
     */
    private function getOtherPartyUser(Conversation $conversation, $viewer): ?User
    {
        $viewerBuyerId = $this->myBuyerId($viewer->USR_ID);
        $viewerIsBuyer = $viewerBuyerId !== null
            && $conversation->BUY_ID === $viewerBuyerId;

        return $viewerIsBuyer
            ? $conversation->farmer?->buyer?->user
            : Buyer::with('user')->find($conversation->BUY_ID)?->user;
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
     * A datetime column as an explicit UTC ISO-8601 string. The database keeps
     * plain `datetime` values (no zone), and the app's timezone is UTC, so
     * without a marker the mobile app would read the wall clock as a *local*
     * time on every device that is not itself UTC — exactly why the recipient
     * saw "6 PM" for a message sent at "2 AM". Appending the offset lets
     * Flutter's `DateTime.parse` treat it as UTC and `.toLocal()` render it in
     * the viewer's own timezone.
     */
    private function utc($datetime): ?string
    {
        if (! $datetime) {
            return null;
        }

        return Carbon::parse($datetime)
            ->setTimezone(config('app.timezone'))
            ->toIso8601String();
    }

    /**
     * A message plus the one derived field the app needs: whether it is mine.
     * Comparing the sender against the caller's own USR_ID means the identical
     * payload renders correctly for the buyer and the seller, with no role
     * column anywhere in the schema.
     */
    private function formatMessage(Message $message, $viewerId): array
    {
        $latitude = $message->MSG_LATITUDE === null
            ? null
            : (float) $message->MSG_LATITUDE;
        $longitude = $message->MSG_LONGITUDE === null
            ? null
            : (float) $message->MSG_LONGITUDE;

        return [
            'id' => $message->MSG_ID,
            'conversation_id' => $message->CONV_ID,
            'sender_id' => $message->USR_ID,
            'is_mine' => $message->USR_ID === $viewerId,
            'content' => $message->MSG_CONTENT,
            'image_url' => $message->MSG_IMAGE_PATH,
            // A pin is one more kind of payload alongside text and a photo. The
            // two coordinates are sent together or not at all, so the app can
            // treat "latitude present" as the whole signal.
            'latitude' => $latitude,
            'longitude' => $longitude,
            'location_label' => $message->MSG_LOCATION_LABEL,
            // The farm a shared location belongs to, so the app can open the
            // same directions screen a listing's Directions button uses.
            'farm_id' => $message->MSG_FARM_ID,
            'is_read' => (bool) $message->MSG_IS_READ,
            'created_at' => $this->utc($message->MSG_CREATED_AT),
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
            ? $conversation->farmer?->buyer?->user
            : Buyer::with('user')->find($conversation->BUY_ID)?->user;

        return [
            'id' => $conversation->CONV_ID,
            'listing_id' => $conversation->LST_ID,
            'my_role' => $viewerIsBuyer ? 'BUYER' : 'SELLER',
            'buy_request' => $conversation->BRQ_ID ? [
                'id' => $conversation->BRQ_ID,
                'crop' => $conversation->buyRequest?->BRQ_CROP,
                'quantity_kg' => (float) $conversation->buyRequest?->BRQ_QUANTITY_KG,
                'removed' => $conversation->buyRequest?->BRQ_REMOVED_AT !== null,
            ] : null,
            'buyer_id' => $conversation->BUY_ID,
            'seller_farmer_id' => $conversation->FMR_ID,
            'farm_id' => $conversation->FRM_ID,
            'last_message' => $this->visiblePreviewFor($conversation->CONV_ID),
            'last_message_at' => $this->utc($conversation->CNV_LAST_MESSAGE_AT),
            'created_at' => $this->utc($conversation->CONV_CREATED_AT),
            'listing' => $listing ? $this->formatListing($listing) : null,
            'farm' => [
                'id' => $listing?->farm?->FRM_ID ?? $conversation->FRM_ID,
                'name' => $listing?->farm?->FRM_NAME ?? $conversation->farm?->FRM_NAME,
                'barangay' => $listing?->farm?->FRM_BARANGAY ?? $conversation->farm?->FRM_BARANGAY,
            ],
            'other_party' => [
                'id' => $otherUser?->USR_ID,
                'name' => $otherUser?->USR_NAME,
                'photo' => $otherUser?->USR_PHOTO_PATH,
                'status' => $otherUser?->USR_STATUS,
            ],
        ];
    }

    /**
     * The text a thread preview should show for a message.
     *
     * Plain text is truncated to the width CNV_LAST_MESSAGE stores, so a
     * preview is the same length whether it came from the row or from the query
     * below. A photo-only message has no readable text, so it becomes "Photo".
     * A shared pin has no text of its own either, so it previews as
     * "Shared location" (with its label when there is one).
     */
    private function previewFor(
        ?string $imageUrl,
        string $content,
        bool $hasLocation = false,
        ?string $locationLabel = null
    ): string {
        if (trim($content) !== '') {
            return mb_substr($content, 0, 500);
        }

        if ($hasLocation) {
            $label = trim((string) $locationLabel);

            return mb_substr(
                $label === '' ? 'Shared location' : "Shared location: {$label}",
                0,
                500
            );
        }

        return $imageUrl ? 'Photo' : '';
    }

    /**
     * The newest message the viewer is allowed to see, for the thread preview.
     *
     * CNV_LAST_MESSAGE is a copy of the last message's text kept on the
     * conversation row, and it is not touched when a message is hidden. So a
     * moderator who hides the final message in a thread has taken it out of the
     * message list and left it sitting in the conversation list — the app would
     * still show the reported text, which is the whole thing the button was
     * supposed to stop.
     *
     * Ordered by MSG_SEQ rather than the timestamp for the same reason the
     * message history is: two messages in one thread can share a timestamp, and
     * the sequence is monotonic.
     *
     * Reads MSG_IMAGE_PATH and the location columns too, so a photo-only or
     * pin-only message previews the same way the stored copy did. Null when
     * every message in the thread is hidden. There is deliberately no fallback
     * to CNV_LAST_MESSAGE: the stored copy is the text of whichever message
     * came last, hidden or not, so falling back to it would put the reported
     * text straight back into the list — the one thing the hidden button exists
     * to prevent.
     *
     * @return string|null
     */
    private function visiblePreviewFor(string $conversationId): ?string
    {
        $message = Message::where('CONV_ID', $conversationId)
            ->visible()
            ->orderByDesc('MSG_SEQ')
            ->first([
                'MSG_CONTENT',
                'MSG_IMAGE_PATH',
                'MSG_LATITUDE',
                'MSG_LONGITUDE',
                'MSG_LOCATION_LABEL',
            ]);

        if (! $message) {
            return null;
        }

        return $this->previewFor(
            $message->MSG_IMAGE_PATH,
            (string) $message->MSG_CONTENT,
            $message->MSG_LATITUDE !== null && $message->MSG_LONGITUDE !== null,
            $message->MSG_LOCATION_LABEL
        );
    }
}
