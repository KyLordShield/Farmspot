<?php

namespace App\Http\Controllers;

use App\Models\CropCategory;
use App\Models\Listing;
use Illuminate\Http\Request;

class ListingController extends Controller
{
    public function index(Request $request)
    {
        $listings = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $q->where('LST_ID', 'like', '%' . $request->search . '%')
                      ->orWhereHas('category', function ($cq) use ($request) {
                          $cq->where('CAT_NAME', 'like', '%' . $request->search . '%');
                      })
                      ->orWhereHas('farm', function ($fq) use ($request) {
                          $fq->where('FRM_NAME', 'like', '%' . $request->search . '%');
                      });
                });
            })
            ->when($request->filled('category'), function ($query) use ($request) {
                $query->where('CAT_ID', $request->category);
            })
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('LST_AVAILABILITY', $request->status);
            })
            ->orderBy('LST_CREATED_AT', 'desc')
            ->paginate(10)
            ->withQueryString();

        $categories = CropCategory::orderBy('CAT_NAME')->get();

        return view('listings', compact('listings', 'categories'));
    }

    public function show($id)
    {
        $listing = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->where('LST_ID', $id)
            ->firstOrFail();

        return view('listings.show', compact('listing'));
    }

    public function edit($id)
    {
        $listing = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->where('LST_ID', $id)
            ->firstOrFail();

        $categories = CropCategory::orderBy('CAT_NAME')->get();

        return view('listings.edit', compact('listing', 'categories'));
    }

    public function update(Request $request, $id)
    {
        $listing = Listing::where('LST_ID', $id)->firstOrFail();

        $validated = $request->validate([
            'LST_CROP_ICON' => ['nullable', 'string', 'max:255'],
            'LST_STATUS' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
            'LST_AVAILABILITY' => ['required', 'in:ACTIVE,NOT_AVAILABLE,REMOVED'],
            'LST_HARVEST_DATE' => ['nullable', 'date'],
            'CAT_ID' => ['required', 'exists:crop_category,CAT_ID'],
        ]);

        $listing->update([
            'LST_CROP_ICON' => $validated['LST_CROP_ICON'],
            'LST_STATUS' => $validated['LST_STATUS'],
            'LST_AVAILABILITY' => $validated['LST_AVAILABILITY'],
            'LST_HARVEST_DATE' => $validated['LST_HARVEST_DATE'],
            'CAT_ID' => $validated['CAT_ID'],
            'LST_UPDATED_AT' => now(),
        ]);

        return redirect()->route('listings')->with('success', 'Listing updated successfully.');
    }

    public function destroy($id)
    {
        $listing = Listing::where('LST_ID', $id)->firstOrFail();

        $listing->LST_AVAILABILITY = 'REMOVED';
        $listing->LST_UPDATED_AT = now();
        $listing->save();

        return redirect()->route('listings')->with('success', 'Listing removed successfully.');
    }
}