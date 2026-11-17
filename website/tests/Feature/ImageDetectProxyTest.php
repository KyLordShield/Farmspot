<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\ImageDetectController;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ImageDetectProxyTest extends TestCase
{
    public function test_proxy_sends_server_token_and_returns_only_detections(): void
    {
        config(['services.image_detect.url' => 'https://scanner.test', 'services.image_detect.token' => 'server-secret']);
        Http::fake(['scanner.test/*' => Http::response(['detections' => [['name' => 'kamatis', 'confidence' => 0.9]], 'private_detail' => 'hidden'])]);
        $request = Request::create('/api/image-search/detect', 'POST', [], [], ['file' => UploadedFile::fake()->createWithContent('crop.png', base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII='))]);
        $response = (new ImageDetectController)->detect($request);
        $this->assertSame(200, $response->status());
        $this->assertSame(['detections'], array_keys($response->getData(true)));
        Http::assertSent(fn ($r) => $r->hasHeader('Authorization', 'Bearer server-secret') && $r->url() === 'https://scanner.test/detect');
    }

    public function test_upstream_failure_does_not_expose_its_body(): void
    {
        config(['services.image_detect.url' => 'https://scanner.test', 'services.image_detect.token' => 'server-secret']);
        Http::fake(['scanner.test/*' => Http::response('private upstream error', 403)]);
        $request = Request::create('/api/image-search/detect', 'POST', [], [], ['file' => UploadedFile::fake()->createWithContent('crop.png', base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII='))]);
        $response = (new ImageDetectController)->detect($request);
        $this->assertSame(502, $response->status());
        $this->assertStringNotContainsString('private upstream error', $response->getContent());
    }
}

