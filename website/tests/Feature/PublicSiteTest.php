<?php

namespace Tests\Feature;

use App\Models\User;
use Tests\TestCase;

class PublicSiteTest extends TestCase
{
    public function test_public_page_shows_price_operator_and_policy_links_without_sign_in(): void
    {
        config(['public_site' => [
            'business_name' => 'Example Fruit Stand',
            'business_address' => null,
            'support_email' => 'support@example.test',
            'support_phone' => '09123456789',
        ]]);

        $this->get('/farmspot')->assertOk()
            ->assertSee('Example Fruit Stand')
            ->assertSee('₱2.00')
            ->assertSee('support@example.test')
            ->assertSee('PayMongo test mode')
            ->assertSee(route('legal.show', 'terms'))
            ->assertSee(route('legal.show', 'privacy'));

        $this->get('/')->assertOk()->assertDontSee('href="'.route('login').'"', false);
        $this->get('/dashboard')->assertRedirect(route('login'));
    }

    public function test_incomplete_business_details_do_not_publish_a_placeholder_page(): void
    {
        config(['public_site' => [
            'business_name' => null,
            'business_address' => null,
            'support_email' => null,
            'support_phone' => null,
        ]]);

        $this->get('/farmspot')->assertNotFound();
    }

    public function test_public_and_policy_pages_do_not_link_to_admin_login(): void
    {
        foreach (['/farmspot', '/legal/terms', '/legal/privacy', '/legal/seller', '/legal/verification'] as $path) {
            $this->get($path)->assertOk()
                ->assertDontSee('href="'.route('login').'"', false)
                ->assertSee('href="'.route('public.home').'"', false);
        }
        $this->get('/login')->assertOk()->assertHeader('X-Robots-Tag', 'noindex, nofollow')
            ->assertSee('<meta name="robots" content="noindex, nofollow">', false);
    }

    public function test_admin_pages_require_login_and_reject_regular_accounts(): void
    {
        foreach (['/dashboard', '/reports', '/users'] as $path) {
            $this->get($path)->assertRedirect(route('login'));
        }

        $this->actingAs(new User(['USR_ID' => 'BUY001', 'USR_ROLE' => 'GENERAL_USER']));
        foreach (['/dashboard', '/reports', '/users'] as $path) {
            $this->get($path)->assertForbidden();
        }
    }
}
