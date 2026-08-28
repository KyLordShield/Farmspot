<?php

namespace App\Http\Controllers;

use App\Models\Whitelist;

class WhitelistController extends Controller
{
    public function index()
    {
        $whitelists = Whitelist::orderBy('WLST_ADDED_AT', 'desc')
                               ->paginate(10);

        return view('whitelist', compact('whitelists'));
    }
}