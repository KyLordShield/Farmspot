<?php

namespace App\Http\Controllers;

use App\Models\Listing;

class ListingController extends Controller
{
    public function index()
    {
        $listings = Listing::paginate(10);

        return view('listings', compact('listings'));
    }
}