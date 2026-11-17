<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;

class ImageDetectController extends Controller
{
    public function detect(Request $request)
    {
        $request->validate(['file' => 'required|image|mimes:jpg,jpeg,png,webp|max:10240']);
        $url = config('services.image_detect.url');
        $token = config('services.image_detect.token');
        if (! $url || ! $token) {
            return response()->json(['message' => 'The crop scanner is unavailable.'], 503);
        }

        $file = $request->file('file');
        try {
            $response = Http::withToken($token)->acceptJson()
                ->connectTimeout(15)->timeout(150)
                ->attach('file', file_get_contents($file->getRealPath()), 'crop.'.$file->extension())
                ->post(rtrim($url, '/').'/detect');
        } catch (ConnectionException $e) {
            return response()->json(['message' => 'The crop scanner took too long. Please try again.'], 504);
        }

        $data = $response->json();
        if (! $response->successful() || ! is_array($data) || ! isset($data['detections']) || ! is_array($data['detections'])) {
            // Never expose the upstream body, headers, or credentials to the app.
            return response()->json(['message' => 'The crop scanner is unavailable. Please try again.'], 502);
        }

        return response()->json(['detections' => $data['detections']]);
    }
}
