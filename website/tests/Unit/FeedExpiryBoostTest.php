<?php

namespace Tests\Unit;

use App\Http\Controllers\Api\Concerns\RanksFeedListings;
use App\Models\Listing;
use Tests\TestCase;

class FeedExpiryBoostTest extends TestCase
{
    private function score(?string $expiry, string $status = 'AVAILABLE_NOW', string $availability = 'ACTIVE', ?float $affinity = null, ?float $rating = null, int $reviews = 0): float
    {
        $ranker = new class
        {
            use RanksFeedListings;

            public function score(Listing $listing, ?float $affinity, ?float $rating, int $reviews): float
            {
                return $this->feedScore($listing, $rating, $reviews, 0, $affinity);
            }
        };

        return $ranker->score(new Listing([
            'LST_CREATED_AT' => now()->subDays(2),
            'LST_EXPIRY_DATE' => $expiry,
            'LST_STATUS' => $status,
            'LST_AVAILABILITY' => $availability,
        ]), $affinity, $rating, $reviews);
    }

    public function test_boost_applies_only_inside_the_next_three_days(): void
    {
        $this->freezeTime();
        $base = $this->score(null);
        foreach ([now()->addSecond(), now()->addDay(), now()->addDays(3)] as $expiry) {
            $this->assertEqualsWithDelta($base + 0.05, $this->score($expiry->toDateTimeString()), 0.000001);
        }
        foreach ([now()->subSecond(), now(), now()->addDays(3)->addSecond(), now()->addDays(10)] as $expiry) {
            $this->assertSame($base, $this->score($expiry->toDateTimeString()));
        }
    }

    public function test_unavailable_and_unharvested_listings_receive_no_boost(): void
    {
        $this->freezeTime();
        $base = $this->score(null);
        $soon = now()->addDay()->toDateTimeString();
        $this->assertSame($base, $this->score($soon, 'SOON_TO_HARVEST'));
        $this->assertSame($base, $this->score($soon, 'NOT_AVAILABLE'));
        $this->assertSame($base, $this->score($soon, availability: 'INACTIVE'));
    }

    public function test_boost_does_not_overpower_strong_history_or_quality(): void
    {
        $this->freezeTime();
        $ending = $this->score(now()->addDay()->toDateTimeString());
        $this->assertGreaterThan($ending, $this->score(null, affinity: 1));
        $this->assertGreaterThan($ending, $this->score(null, rating: 5, reviews: 30));
    }
}
