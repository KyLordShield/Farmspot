<?php

namespace Tests\Feature;

use App\Services\RenewalCropVerifier;
use App\Support\CropShelfLife;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class RenewalCropVerifierTest extends TestCase
{
    private function photos(): array
    {
        config(['services.image_detect.url' => 'https://scanner.test', 'services.image_detect.token' => 'test-token']);

        return [
            'photos.0' => UploadedFile::fake()->create('first.jpg', 1, 'image/jpeg'),
            'photos.1' => UploadedFile::fake()->create('second.jpg', 1, 'image/jpeg'),
        ];
    }

    public function test_each_photo_is_checked_with_the_scanner(): void
    {
        Http::fake(['scanner.test/*' => Http::response(['detections' => [['name' => 'kamatis']]])]);

        (new RenewalCropVerifier)->verify($this->photos(), CropShelfLife::detectorName('Tomatoes'));

        Http::assertSentCount(2);
        Http::assertSent(fn ($request) => $request->hasHeader('Authorization', 'Bearer test-token')
            && $request->url() === 'https://scanner.test/detect?include_condition=true');
        $this->assertSame(5, CropShelfLife::days('Tomatoes'));
        $this->assertSame(10, CropShelfLife::days('Carrot'));
    }

    public function test_accepted_chili_stages_produce_different_estimates(): void
    {
        Http::fake(['scanner.test/*' => Http::sequence()
            ->push(['detections' => [['name' => 'chili', 'condition' => 'chili_unripe']]])
            ->push(['detections' => [['name' => 'chili', 'condition' => 'chili_ripe']]])]);

        $this->assertSame(
            ['photos.0' => 21, 'photos.1' => 14],
            (new RenewalCropVerifier)->verify($this->photos(), 'chili'),
        );
    }

    public function test_leafy_crop_flags_do_not_get_a_countdown(): void
    {
        $this->assertSame(21, CropShelfLife::assessment('cabbage', 'cabbage_fresh')['days']);
        $this->assertSame(7, CropShelfLife::assessment('lettuce', 'lettuce_fresh')['days']);
        $this->assertNull(CropShelfLife::assessment('cabbage', 'cabbage_rotten'));
        $this->assertNull(CropShelfLife::assessment('lettuce', 'lettuce_visibly_degraded'));
        $this->assertNull(CropShelfLife::assessment('kamatis', 'chili_ripe'));
    }

    public function test_deterioration_does_not_prevent_renewal_photo_verification(): void
    {
        Http::fake(['scanner.test/*' => Http::response([
            'detections' => [['name' => 'lettuce', 'condition' => 'lettuce_visibly_degraded']],
        ])]);

        $this->assertSame(
            ['photos.0' => null, 'photos.1' => null],
            (new RenewalCropVerifier)->verify($this->photos(), 'lettuce'),
        );
    }

    public function test_a_mismatching_secondary_photo_is_rejected(): void
    {
        Http::fake(['scanner.test/*' => Http::sequence()
            ->push(['detections' => [['name' => 'kamatis']]])
            ->push(['detections' => [['name' => 'cucumber']]])]);

        try {
            (new RenewalCropVerifier)->verify($this->photos(), 'kamatis');
            $this->fail('A cucumber photo must not renew a tomato listing.');
        } catch (ValidationException $error) {
            $this->assertArrayHasKey('photos.1', $error->errors());
        }
    }
}
