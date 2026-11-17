<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class UserMembershipFilterTest extends TestCase
{
    use RefreshDatabase;

    public function test_membership_filters_respect_expiry_and_combine_with_other_filters(): void
    {
        $this->travelTo(now()->startOfSecond());

        foreach ([
            ['ADMIN1', 'ADMIN', null],
            ['PAID01', 'GENERAL_USER', now()->addDay()],
            ['OLD001', 'GENERAL_USER', now()->subDay()],
            ['EDGE01', 'GENERAL_USER', now()],
            ['FREE01', 'GENERAL_USER', null],
        ] as [$id, $role, $expiry]) {
            User::forceCreate([
                'USR_ID' => $id,
                'USR_NAME' => 'Member '.$id,
                'USR_EMAIL' => $id.'@test.local',
                'USR_PASSWORD' => bcrypt('password123'),
                'USR_MOBILE_NUMBER' => '09123456789',
                'USR_ROLE' => $role,
                'USR_IS_SELLER' => 0,
                'USR_STATUS' => 'ACTIVE',
                'USR_CREATED_AT' => now(),
                'USR_PREMIUM_EXPIRES_AT' => $expiry,
            ]);
        }

        $this->actingAs(User::findOrFail('ADMIN1'));

        $this->get('/users?membership=premium&role=BUYER&status=ACTIVE&search=Member')
            ->assertOk()
            ->assertViewHas('users', fn ($users) => $users->pluck('USR_ID')->all() === ['PAID01'])
            ->assertSee('aria-label="Premium member"', false);

        $this->get('/users?membership=standard&role=BUYER')
            ->assertOk()
            ->assertViewHas('users', fn ($users) => $users->total() === 3
                && $users->pluck('USR_ID')->sort()->values()->all() === ['EDGE01', 'FREE01', 'OLD001'])
            ->assertDontSee('aria-label="Premium member"', false);

        $this->get('/users')->assertOk()
            ->assertViewHas('users', fn ($users) => $users->total() === 5);
    }
}
