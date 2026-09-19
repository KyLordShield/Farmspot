<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\CloudinaryImage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

class UserController extends Controller
{
    /**
     * Edit the buyer's own profile. JSON-only, any combination of name,
     * mobile_number and address — only provided fields are updated.
     *
     * Deliberately out of scope here: email and password can NOT be changed
     * through this endpoint, keeping it simple and read-consistent with the
     * account-creation flow.
     *
     * Returns the full, freshly-saved user object (which now includes
     * USR_ADDRESS and USR_PHOTO_PATH).
     */
    public function update(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:150'],
            'mobile_number' => [
                'sometimes',
                'string',
                'max:20',
                // Same uniqueness semantics as registration, scoped to exclude
                // the current user so keeping your own number is fine.
                Rule::unique('user', 'USR_MOBILE_NUMBER')->ignore($user->USR_ID, 'USR_ID'),
            ],
            'address' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        if (array_key_exists('name', $validated)) {
            $user->USR_NAME = $validated['name'];
        }

        if (array_key_exists('mobile_number', $validated)) {
            $user->USR_MOBILE_NUMBER = $validated['mobile_number'];
        }

        // Explicit null clears the address back to empty.
        if (array_key_exists('address', $validated)) {
            $user->USR_ADDRESS = $validated['address'];
        }

        $user->save();

        return response()->json([
            'message' => 'Profile updated successfully.',
            'user' => $user,
        ]);
    }

    /**
     * Replace the buyer's profile photo. Multipart, single `photo` field.
     *
     * Uploads to Cloudinary under profile-photos/{user_id}/{filename} (the same
     * folder convention farm/listing photos use), then swaps USR_PHOTO_PATH to
     * the new URL and only afterwards destroys the previous Cloudinary asset —
     * a failed upload never loses the current photo.
     *
     * Returns the updated user object with the fresh photo URL.
     */
    public function uploadPhoto(Request $request)
    {
        $request->validate([
            'photo' => ['required', 'image', 'max:5120'],
        ]);

        $user = $request->user();
        $oldUrl = $user->USR_PHOTO_PATH;

        $photo = $request->file('photo');
        $extension = $photo->getClientOriginalExtension() ?: 'jpg';
        $path = "profile-photos/{$user->USR_ID}/" . uniqid() . ".{$extension}";

        Storage::disk('cloudinary')->put($path, $photo->getRealPath());
        $newUrl = Storage::disk('cloudinary')->url($path);

        $user->USR_PHOTO_PATH = $newUrl;
        $user->save();

        // Best-effort cloud cleanup of the replaced asset, after the new file
        // is uploaded and the DB has switched over.
        if ($oldUrl !== $newUrl) {
            CloudinaryImage::deleteByUrl($oldUrl);
        }

        return response()->json([
            'message' => 'Profile photo updated successfully.',
            'user' => $user,
        ]);
    }
}