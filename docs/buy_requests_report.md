# Buy requests and existing chat integration

Premium buyers post requests from Profile or Home > My Buy Requests. The server requires active premium access to create a request. A request has crop, quantity in kg, one-time/weekly frequency, optional note, optional pickup/delivery preference and optional explicitly confirmed map pin. No expiry, fulfilled/closed state, or radius is used. Requests remain posted after premium ends; owners can still manage/remove them.

Approved sellers access the board from My Farm > Buyer Requests, without purchasing premium. The board supports crop search, includes all matching requests, and sorts shared map pins by distance from the seller's nearest approved farm. Requests without a location remain visible. A precise pin is supplied only after the buyer chooses a point in the map picker and confirms it. No fallback camera location is saved automatically. The board returns the selected coordinates only for a confirmed pin; requests without one display No location shared. Old approximate locations are not relabelled as pins.

Message buyer starts/reuses one conversation per request and seller in the existing conversation/message tables. The existing inbox, messages, read states, photos, farm-location sharing and reporting remain in use. No message is sent automatically. The request owner sees seller conversations from My Buy Requests or their existing inbox.

Removing a request is owner-only and soft-removes it from discovery. Existing chats remain accessible. Deactivated buyers' requests are hidden; new contact requires an approved seller and an active buyer. Premium is not required for seller contact or continuing a chat.

Database: new buy_request table; nullable BRQ_ID foreign key and unique (BRQ_ID, FMR_ID) added to conversation. No separate response or messaging table. Existing listings and premium dates are not modified. Migration applied locally; apply 2026_10_24_000002_create_buy_requests.php on any other server before updating the app.

Validation: MySQL feature tests cover requests plus existing messaging; Flutter tests cover real API payloads, form posting, confirmed/failed deletion, request-context parsing and opening the existing chat.


## Crop selection, calling, and map pins

GET /api/buy-request-crops supplies a canonical crop catalog with local aliases from config/buy_request_crops.php. The app suggests canonical names for partial text, common typos, joined text, and aliases (for example cabbge, Ineedcabbage, and repolyo suggest Cabbage). The buyer must select a suggestion; descriptions belong in the note. The server rejects noncanonical free-text crop names. This improves consistent crop matching; it does not add automatic inventory notifications.

Approved sellers receive the buyer's profile phone number with the request. Call buyer launches the external phone app via a tel URI; there is no in-app calling. Missing/invalid numbers disable calling while messaging remains available. The posting form explains the phone sharing.

Migration 2026_10_24_000003_add_explicit_buy_request_pins.php adds BRQ_HAS_PIN and increases the two coordinate columns to seven decimal places. Existing coarse locations keep BRQ_HAS_PIN=false. No new tables are added for these enhancements. Migration applied locally.
