<?php

namespace Tests\Feature;

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

        $this->get('/')->assertRedirect(route('login'));
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
}
