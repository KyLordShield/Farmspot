<?php

namespace App\Http\Controllers;

use App\Models\Farm;
use Illuminate\Support\Facades\Http;

class SellerDocumentController extends Controller
{
    public function show(string $id, string $document)
    {
        $field = ['id' => 'FRM_VERIFICATION_DOC_PATH', 'permit' => 'FRM_FARM_CERTIFICATE_PATH'][$document] ?? null;
        abort_unless($field, 404);
        $url = Farm::findOrFail($id)->getAttribute($field);
        $parts = is_string($url) ? parse_url($url) : false;
        abort_unless($parts && ($parts['scheme'] ?? '') === 'https'
            && ($parts['host'] ?? '') === 'res.cloudinary.com'
            && ! isset($parts['user']) && ! isset($parts['pass']) && ! isset($parts['port']), 404);

        try {
            $upstream = Http::timeout(20)->connectTimeout(5)
                ->withOptions(['allow_redirects' => false, 'stream' => true])->get($url);
            abort_unless($upstream->ok(), 502, 'Document preview is unavailable.');
            $mime = strtolower(trim(explode(';', $upstream->header('Content-Type'))[0]));
            abort_unless(in_array($mime, ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf'], true), 415, 'Unsupported document preview.');
            $stream = $upstream->toPsrResponse()->getBody();
            $body = '';
            while (! $stream->eof() && strlen($body) <= 10 * 1024 * 1024) {
                $body .= $stream->read(65536);
            }
            $stream->close();
            abort_if(strlen($body) > 10 * 1024 * 1024, 413, 'Document is too large to preview.');
        } catch (\Illuminate\Http\Client\ConnectionException $error) {
            abort(502, 'Document preview is unavailable. Please try again.');
        }

        return response($body, 200, [
            'Content-Type' => $mime,
            'Content-Disposition' => 'inline',
            'Cache-Control' => 'private, no-store, max-age=0',
            'X-Content-Type-Options' => 'nosniff',
            'X-Frame-Options' => 'SAMEORIGIN',
            'Referrer-Policy' => 'no-referrer',
        ]);
    }
}
