<?php

namespace App\Http\Controllers;

use App\Models\Whitelist;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
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

        if ($whitelist->WLST_IS_ACTIVE == 1) {
            $whitelist->WLST_IS_ACTIVE = 0;
            $whitelist->USR_DEACTIVATED_ID = Auth::user()->USR_ID;
            $message = 'Mobile number deactivated successfully.';
        } else {
            $whitelist->WLST_IS_ACTIVE = 1;
            $whitelist->USR_DEACTIVATED_ID = null;
            $message = 'Mobile number reactivated successfully.';
        }

        $whitelist->save();

        return redirect()->route('whitelist')->with('success', $message);
    }

    public function show($id)
    {
        $whitelist = Whitelist::with(['addedBy', 'deactivatedBy'])
            ->where('WLST_ID', $id)
            ->firstOrFail();

        return view('whitelist.show', compact('whitelist'));
    }
}