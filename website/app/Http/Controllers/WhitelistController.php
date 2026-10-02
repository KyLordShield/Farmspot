<?php

namespace App\Http\Controllers;

use App\Models\Farm;
use App\Models\Farmer;
use App\Models\User;
use App\Models\Whitelist;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class WhitelistController extends Controller
{
    public function index(Request $request)
    {
        $whitelists = Whitelist::with(['addedBy', 'deactivatedBy'])
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where('WLST_MOBILE_NUMBER', 'like', '%' . $request->search . '%');
            })
            ->when($request->filled('status'), function ($query) use ($request) {
                if ($request->status == 'Active') {
                    $query->where('WLST_IS_ACTIVE', 1);
                } elseif ($request->status == 'Inactive') {
                    $query->where('WLST_IS_ACTIVE', 0);
                }
            })
            ->orderBy('WLST_ADDED_AT', 'desc')
            ->paginate(10)
            ->withQueryString();

        return view('whitelist', compact('whitelists'));
    }

    public function create()
    {
        return view('whitelist.create');
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'WLST_MOBILE_NUMBER' => [
                'required',
                'string',
                'max:20',
                'unique:whitelist,WLST_MOBILE_NUMBER',
            ],
        ], [
            'WLST_MOBILE_NUMBER.unique' => 'This mobile number is already whitelisted.',
        ]);

        do {
            $id = strtoupper(Str::random(6));
        } while (Whitelist::where('WLST_ID', $id)->exists());

        Whitelist::create([
            'WLST_ID' => $id,
            'WLST_MOBILE_NUMBER' => $validated['WLST_MOBILE_NUMBER'],
            'WLST_IS_ACTIVE' => 1,
            'WLST_ADDED_AT' => now(),
            'USR_ADDED_ID' => Auth::user()->USR_ID,
            'USR_DEACTIVATED_ID' => null,
        ]);

        return redirect()->route('whitelist')->with('success', 'Mobile number added to whitelist successfully.');
    }

    public function toggleStatus($id)
    {
        $whitelist = Whitelist::where('WLST_ID', $id)->firstOrFail();

        $wasActive = $whitelist->WLST_IS_ACTIVE == 1;

        if ($wasActive) {
            $whitelist->WLST_IS_ACTIVE = 0;
            $whitelist->USR_DEACTIVATED_ID = Auth::user()->USR_ID;
            $message = 'Mobile number deactivated successfully.';
        } else {
            $whitelist->WLST_IS_ACTIVE = 1;
            $whitelist->USR_DEACTIVATED_ID = null;
            $message = 'Mobile number reactivated successfully.';
        }

        $whitelist->save();

        // Only the deactivation direction changes anything for the person
        // behind the number. Reactivation is deliberately left alone here: the
        // seller flags were turned off irreversibly by the deactivation, and
        // deciding what a restore should bring back is a separate decision from
        // the one that turned it off.
        if ($wasActive) {
            $this->deactivateSellerFor($whitelist->WLST_MOBILE_NUMBER);
        }

        return redirect()->route('whitelist')->with('success', $message);
    }

    /**
     * Turn a whitelisted number's seller off, and tell them.
     *
     * The whitelist is the gate on becoming a seller: a number has to be on it
     * before an account can list produce (see FarmController@store). Turning a
     * number off therefore has to mean more than "this number is off the
     * list" — the account it belongs to must actually stop being a seller,
     * otherwise a person who is no longer authorised keeps a live seller
     * profile, a farm on the map, and produce on sale.
     *
     * Nothing is deleted. USR_IS_SELLER and FMR_SELLER_MODE_ACTIVE are turned
     * off and the map pins are hidden, which is reversible; the listings
     * themselves are left exactly as they are, because whether produce that is
     * already posted should be pulled is a moderator's call and this button is
     * about the person's authorisation, not about their catalogue.
     *
     * The mobile number is the only link between a whitelist row and a user —
     * there is no FK — which is also why the match is on the exact stored
     * string. Formatting differences are not reconciled here: a number that
     * matches no user simply means there is nobody to notify.
     */
    private function deactivateSellerFor(string $mobileNumber): void
    {
        $user = User::where('USR_MOBILE_NUMBER', $mobileNumber)->first();

        if (! $user) {
            return;
        }

        // USR_IS_SELLER is the app's own flag and FMR_SELLER_MODE_ACTIVE the
        // one on the farmer row. The app reads both, so clearing only one leaves
        // the person half a seller depending on which screen you open.
        // FMR_ID is found through the buyer row, since a farmer hangs off a
        // buyer and not directly off a user.
        $farmer = Farmer::whereIn('BUY_ID', function ($query) use ($user) {
            $query->select('BUY_ID')->from('buyer')->where('USR_ID', $user->USR_ID);
        })->first();

        if (! $user->USR_IS_SELLER && ! $farmer?->FMR_SELLER_MODE_ACTIVE) {
            return;
        }

        DB::transaction(function () use ($user, $farmer) {
            $user->USR_IS_SELLER = 0;
            $user->save();

            if ($farmer) {
                $farmer->FMR_SELLER_MODE_ACTIVE = 0;
                $farmer->save();

                // Hide the map pins so the farm stops appearing as somewhere to
                // buy. The farm row itself is untouched, so re-enabling the
                // pins is a single update if the number is restored.
                Farm::where('FMR_ID', $farmer->FMR_ID)
                    ->update(['FRM_PIN_ACTIVE' => 0]);
            }
        });

        app(NotificationService::class)->notify(
            $user->USR_ID,
            'SELLER_DEACTIVATED',
            'Seller mode turned off',
            'Your seller mode was turned off. Your listings are still saved. Contact the FarmSpot team if you think this is a mistake.',
        );
    }

    public function show($id)
    {
        $whitelist = Whitelist::with(['addedBy', 'deactivatedBy'])
            ->where('WLST_ID', $id)
            ->firstOrFail();

        return view('whitelist.show', compact('whitelist'));
    }
}