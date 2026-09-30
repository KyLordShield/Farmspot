<?php

namespace App\Support;

use App\Models\Buyer;
use App\Models\ContactLog;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\FarmVisitLog;
use App\Models\Listing;
use App\Models\SearchLog;
use App\Models\User;

/**
 * The assistant's read-only tools.
 *
 * One rule governs this whole class: a tool's arguments may never include a
 * user id, and every query is rooted at the User instance built from the
 * authenticated request. The model chooses *which* tool to call and supplies
 * things like a crop name, but it can never point the assistant at somebody
 * else's farm, listings or activity. Authorisation cannot be delegated to a
 * language model.
 *
 * Results are deliberately small and flat. They are fed straight back into the
 * model and billed as input tokens on the follow-up call, so an ORM collection
 * dumped verbatim would be both expensive and harder for the model to read
 * than a handful of named fields.
 */
class AiTools
{
    private ?Farmer $farmer = null;

    private bool $farmerResolved = false;

    public function __construct(private User $user)
    {
    }

    /**
     * Tool definitions in OpenAI function-calling format.
     *
     * Descriptions are terse on purpose. Every request pays for the whole tool
     * list in input tokens, including the many questions that need no tool at
     * all, so each one states the exact trigger rather than a paragraph.
     *
     * @return array<int, array<string, mixed>>
     */
    public static function schemas(): array
    {
        $noArguments = [
            'type' => 'object',
            // cast, not [], so this encodes as {} rather than []
            'properties' => (object) [],
            'required' => [],
        ];

        return [
            [
                'type' => 'function',
                'function' => [
                    'name' => 'get_app_guide',
                    'description' => 'How the FarmSpot app actually works: the real tab names, button labels and tap paths, plus what is not live yet. Call this before giving any "how do I..." or "where do I find..." answer, and use only the labels it returns. Never invent a screen or button name.',
                    'parameters' => $noArguments,
                ],
            ],
            [
                'type' => 'function',
                'function' => [
                    'name' => 'get_my_account',
                    'description' => "The signed-in user's own account: whether they are a buyer or seller, their account status, and whether seller mode is switched on. Use for \"am I a seller\", \"why is my account pending\".",
                    'parameters' => $noArguments,
                ],
            ],
            [
                'type' => 'function',
                'function' => [
                    'name' => 'get_my_farms',
                    'description' => "The signed-in user's own farm(s), including approval status (PENDING_REVIEW, APPROVED, REJECTED) and whether it is visible on the map. Use for \"what's my farm status\", \"is my farm approved yet\", \"why can't I list produce\".",
                    'parameters' => $noArguments,
                ],
            ],
            [
                'type' => 'function',
                'function' => [
                    'name' => 'get_my_listings',
                    'description' => "The signed-in seller's own produce listings with their status and availability, plus counts by status. Use for \"my listings\", \"how many listings do I have\", \"is my pechay still available\".",
                    'parameters' => $noArguments,
                ],
            ],
            [
                'type' => 'function',
                'function' => [
                    'name' => 'get_my_activity',
                    'description' => 'Activity totals for the signed-in user: searches made, farms visited, buyers who contacted them, and sellers they contacted. buyers_who_contacted_me is 0 for anyone without approved listings. Use for "has anyone contacted me", "how many buyers are interested", "am I getting views".',
                    'parameters' => $noArguments,
                ],
            ],
            [
                'type' => 'function',
                'function' => [
                    'name' => 'search_marketplace',
                    'description' => 'Search live produce listings on FarmSpot by crop name, returning the farm, barangay and availability. Use for "who is selling pechay", "where can I buy tomatoes". Never returns contact details.',
                    'parameters' => [
                        'type' => 'object',
                        'properties' => [
                            'crop' => [
                                'type' => 'string',
                                'description' => 'Crop to search for. Partial names are fine, e.g. "pechay" or "tomato".',
                            ],
                        ],
                        'required' => ['crop'],
                    ],
                ],
            ],
        ];
    }

    /**
     * Executes one tool call and returns a JSON-encodable result.
     *
     * An unknown or malformed call returns a note rather than throwing, so a
     * confused model gets another turn to recover instead of a 500.
     */
    public function run(string $name, array $arguments): array
    {
        return match ($name) {
            'get_app_guide' => $this->appGuide(),
            'get_my_account' => $this->account(),
            'get_my_farms' => $this->farms(),
            'get_my_listings' => $this->listings(),
            'get_my_activity' => $this->activity(),
            'search_marketplace' => $this->searchMarketplace($arguments),
            default => ['error' => "Unknown tool '$name'."],
        };
    }

    /**
     * The app's real navigation, as data.
     *
     * This lives in a tool rather than the system prompt for two reasons. The
     * model was inventing plausible-looking paths like "Help > Chat" that do
     * not exist, and pinning the truth in the prompt would add roughly 450
     * tokens to *every* request, including the agriculture questions that need
     * no app knowledge at all. As a tool it is only paid for when a how-to
     * question is actually asked.
     *
     * Every label below was read out of the widget source, and the
     * gotchas section records the places where the UI misleads people.
     */
    private function appGuide(): array
    {
        return [
            'tabs' => [
                'buyer' => ['Home', 'Map', 'Insights', 'Profile'],
                'seller' => ['Home', 'Map', 'Insights', 'My Farm', 'Profile'],
            ],
            'buying' => [
                'find a specific crop' => 'Home, tap the search bar at the top, type the crop name, then tap a result.',
                'find produce by photo' => 'Home, tap the camera icon next to the search bar.',
                'see what is near me' => 'Map tab. Farm pins open a farm; tapping produce opens the listing.',
                'contact a seller' => 'Open any produce listing, then tap "Message Seller" at the bottom.',
                'my conversations' => 'Home, tap the speech-bubble icon in the top bar. That is the message inbox.',
            ],
            'selling' => [
                'become a seller' => 'Profile tab, switch on "Become a Seller". If you have no farm yet, this starts farm setup.',
                'farm setup steps' => 'Profile > "Become a Seller" > farm name and description > verification upload > map location > finish. You need a government ID and a farm certificate for your FIRST farm.',
                'add a second farm' => 'My Farm tab, then the "Add Farm" button at the top right. It runs the same setup again. The ID and permit are already on file, so you can skip that step — they are copied over to the new farm automatically.',
                'a seller can own several farms' => 'Yes. One account can run many farms, each with its own approval status, location, listings and stats. When someone says "my farm", ask which one if they have more than one, and never assume there is only one.',
                'switch between farms' => 'My Farm tab. When you own more than one, the farm names appear as tappable chips under the My Farm heading. The stats and listings below always follow the farm you tap.',
                'check my farm status' => 'My Farm tab. Each farm shows Approved, Pending review, or Rejected.',
                'add produce' => 'My Farm, then "Add Crop" beside the "Listings" heading. A listing belongs to the farm you are currently viewing, so switch farms first if you mean the other one. Add a photo, crop, quantity and harvest date.',
                'change or remove a listing' => 'My Farm, tap the three dots on a listing for Edit, change status, or Delete.',
                'edit my farm details' => 'My Farm, then "Edit Farm".',
                'is anyone interested' => 'My Farm shows Profile Views, Buyer Contacts and Active Listings for the farm you are viewing.',
                'mark produce as ready' => 'My Farm, tap a listing then set its status to "Available Now" or "Soon to Harvest".',
            ],
            'profile' => [
                'change my name or photo' => 'Profile tab, tap "Edit Profile".',
                'reach a human' => 'Profile tab, tap "Contact Support".',
            ],
            'listing_status_words' => [
                'Available Now' => 'ready for buyers to buy',
                'Soon to Harvest' => 'listed now for a future harvest',
                'Not Available' => 'sold out or paused',
            ],
            'gotchas' => [
                'The phone back button exits the app from a main tab. Always tell people to move between sections with the tab bar at the bottom.',
                'After finishing farm setup, the button that says "go to Home" returns to Home. Tell people to then tap the My Farm tab.',
                'One account can own several farms. A farm name, its approval status, its listings and its Profile Views / Buyer Contacts figures all belong to that one farm, not to the seller overall. Never merge or add them together.',
                'There is no way to open a listing from the Insights tab. Insights is a read-only summary; to act on a crop, search for it or open it from Home or Map.',
                'The bell icon opens Notifications, but that screen is not live yet and is always empty. Do not send people there expecting alerts.',
                'Contact Support currently shows placeholder contact details rather than a real phone number or email.',
            ],
        ];
    }

    /** The tool names this class can execute. */
    public static function names(): array
    {
        return array_map(fn (array $tool) => $tool['function']['name'], self::schemas());
    }

    private function account(): array
    {
        $farmer = $this->farmer();

        return [
            'name' => $this->user->USR_NAME,
            'account_status' => $this->user->USR_STATUS,
            'is_seller' => (bool) $this->user->USR_IS_SELLER,
            'seller_mode_active' => $farmer ? (bool) $farmer->FMR_SELLER_MODE_ACTIVE : false,
            'has_farm' => $farmer !== null,
        ];
    }

    private function farms(): array
    {
        $farmer = $this->farmer();
        if ($farmer === null) {
            return [
                'has_farm' => false,
                'note' => 'This user has not created a farm yet.',
                'farms' => [],
            ];
        }

        $farms = Farm::where('FMR_ID', $farmer->FMR_ID)
            ->orderBy('FRM_CREATED_AT')
            ->get()
            ->map(fn (Farm $farm) => [
                'farm_name' => $farm->FRM_NAME,
                'barangay' => $farm->FRM_BARANGAY,
                'status' => $farm->FRM_STATUS,
                'visible_on_map' => (bool) $farm->FRM_PIN_ACTIVE,
                'description' => $farm->FRM_DESCRIPTION,
            ])
            ->all();

        return [
            'has_farm' => true,
            'farms' => $farms,
            // Spelled out once so the assistant can explain a rejection in
            // plain language instead of echoing the raw status code.
            'status_meaning' => [
                'PENDING_REVIEW' => 'waiting for an admin to review it',
                'APPROVED' => 'approved, so the farm can list produce',
                'REJECTED' => 'not approved, so listing produce is blocked until it is resubmitted',
            ],
        ];
    }

    private function listings(): array
    {
        $farmer = $this->farmer();
        if ($farmer === null) {
            return [
                'has_listings' => false,
                'note' => 'This user has no farm, so they cannot have listings.',
                'listings' => [],
            ];
        }

        $query = Listing::with('category')->where('FMR_ID', $farmer->FMR_ID);

        $counts = [
            'total' => (clone $query)->count(),
            'available_now' => (clone $query)->where('LST_STATUS', 'AVAILABLE_NOW')->count(),
            'soon_to_harvest' => (clone $query)->where('LST_STATUS', 'SOON_TO_HARVEST')->count(),
            'not_available' => (clone $query)->where('LST_STATUS', 'NOT_AVAILABLE')->count(),
        ];

        $listings = (clone $query)
            ->orderByDesc('LST_UPDATED_AT')
            ->limit(20)
            ->get()
            ->map(fn (Listing $listing) => [
                'crop' => $listing->category?->CAT_NAME ?? $listing->LST_CROP_ICON,
                'status' => $listing->LST_STATUS,
                'availability' => $listing->LST_AVAILABILITY,
                'harvest_date' => $listing->LST_HARVEST_DATE,
                'description' => $listing->LST_DESCRIPTION,
            ])
            ->all();

        return [
            'has_listings' => $counts['total'] > 0,
            'counts' => $counts,
            'status_meaning' => [
                'AVAILABLE_NOW' => 'ready to buy now',
                'SOON_TO_HARVEST' => 'not ready yet, listed for a future harvest',
                'NOT_AVAILABLE' => 'sold out or paused',
            ],
            'listings' => $listings,
        ];
    }

    private function activity(): array
    {
        $userId = $this->user->USR_ID;
        $farmer = $this->farmer();

        // contact_log.USR_ID is whoever tapped the phone or SMS button, so a
        // row belongs to the *buyer*, never to the seller being contacted. An
        // inbound interest count therefore has to be found by listing, and must
        // not filter on USR_ID or it just counts the seller's own taps.
        $buyersWhoContactedMe = 0;
        $ownListingIds = collect();
        if ($farmer !== null) {
            $ownListingIds = Listing::where('FMR_ID', $farmer->FMR_ID)->pluck('LST_ID');
            $buyersWhoContactedMe = $ownListingIds->isEmpty()
                ? 0
                : ContactLog::whereIn('LST_ID', $ownListingIds)->distinct('USR_ID')->count('USR_ID');
        }

        return [
            'searches_made' => SearchLog::where('USR_ID', $userId)->count(),
            'farms_visited' => FarmVisitLog::where('USR_ID', $userId)->count(),
            // Distinct people, not taps: a buyer calling twice is still one
            // interested buyer.
            'buyers_who_contacted_me' => $buyersWhoContactedMe,
            'sellers_i_contacted' => ContactLog::where('USR_ID', $userId)->count(),
            'own_listing_count' => $ownListingIds->count(),
        ];
    }

    private function searchMarketplace(array $arguments): array
    {
        $crop = trim((string) ($arguments['crop'] ?? ''));
        if ($crop === '') {
            return ['error' => 'A crop name is required.'];
        }

        $rows = Listing::query()
            ->select('listing.LST_ID', 'listing.LST_STATUS', 'listing.LST_HARVEST_DATE', 'crop_category.CAT_NAME')
            ->selectSub(Farm::select('FRM_NAME')->whereColumn('FRM_ID', 'listing.FRM_ID')->limit(1), 'farm_name')
            ->selectSub(Farm::select('FRM_BARANGAY')->whereColumn('FRM_ID', 'listing.FRM_ID')->limit(1), 'barangay')
            ->join('crop_category', 'listing.CAT_ID', '=', 'crop_category.CAT_ID')
            ->where('listing.LST_AVAILABILITY', 'ACTIVE')
            ->where(function ($query) use ($crop) {
                $query->where('crop_category.CAT_NAME', 'like', "%{$crop}%")
                    ->orWhere('listing.LST_CROP_ICON', 'like', "%{$crop}%");
            })
            ->orderBy('listing.LST_UPDATED_AT', 'desc')
            ->limit(10)
            ->get();

        return [
            'crop' => $crop,
            'result_count' => count($rows),
            // Contact details are never part of a tool result. Messaging a
            // seller happens in the app, not through the assistant.
            'listings' => $rows->map(fn ($row) => [
                'crop' => $row->CAT_NAME,
                'farm_name' => $row->farm_name,
                'barangay' => $row->barangay,
                'status' => $row->LST_STATUS,
                'harvest_date' => $row->LST_HARVEST_DATE,
            ])->all(),
        ];
    }

    /**
     * The farmer record behind this user, if they have one.
     *
     * A user reaches a farm through buyer -> farmer, which is not obvious from
     * the user row alone.
     */
    private function farmer(): ?Farmer
    {
        if (!$this->farmerResolved) {
            $buyer = Buyer::where('USR_ID', $this->user->USR_ID)->first();
            $this->farmer = $buyer ? Farmer::where('BUY_ID', $buyer->BUY_ID)->first() : null;
            $this->farmerResolved = true;
        }

        return $this->farmer;
    }
}
