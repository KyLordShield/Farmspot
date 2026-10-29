<?php

namespace Tests\Feature;

use App\Models\LegalAcceptance;
use App\Models\User;
use App\Services\LegalPolicies;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class LegalPoliciesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $catalog = json_decode(file_get_contents(resource_path('legal/policies.json')), true);
        $catalog['published'] = false;
        config(['legal.catalog' => $catalog]);
    }

    private function publish(): array
    {
        $catalog = json_decode(file_get_contents(resource_path('legal/policies.json')), true);
        $catalog['published'] = true;
        $catalog['operator_name'] = 'Test Operator';
        $catalog['contact_email'] = 'privacy@example.test';
        $catalog['retention_policy'] = 'Test retention policy';
        $catalog['refund_policy'] = 'Test refund policy';
        config(['legal.catalog' => $catalog]);

        return $catalog;
    }

    private function user(): User
    {
        $id = strtoupper(Str::random(6));

        return User::create(['USR_ID' => $id, 'USR_NAME' => 'Test Person', 'USR_EMAIL' => $id.'@legal.test', 'USR_PASSWORD' => bcrypt('password123'), 'USR_MOBILE_NUMBER' => '09'.$id, 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_CREATED_AT' => now()]);
    }

    private function registration(): array
    {
        return ['USR_NAME' => 'Juan Dela Cruz', 'USR_EMAIL' => 'new@legal.test', 'USR_PASSWORD' => 'password123', 'USR_PASSWORD_confirmation' => 'password123', 'USR_MOBILE_NUMBER' => '09123456789'];
    }

    public function test_draft_documents_are_public_but_cannot_be_accepted_and_legacy_signup_works(): void
    {
        $this->getJson('/api/legal')->assertOk()->assertJsonPath('published', false);
        foreach (['terms', 'privacy', 'seller', 'verification'] as $id) {
            $this->get('/legal/'.$id)->assertOk()->assertSee('Draft for review');
        }
        $this->get('/legal/missing')->assertNotFound();
        $this->postJson('/api/register', $this->registration())->assertCreated();
        $this->assertSame(0, LegalAcceptance::count());
        Sanctum::actingAs(User::firstOrFail());
        $this->postJson('/api/legal/acceptances', ['legal_version' => '2026-10-28-v1', 'documents' => ['seller'], 'accepted' => true])->assertUnprocessable();
        $this->assertSame(0, LegalAcceptance::count());
    }

    public function test_just_setting_published_does_not_activate_incomplete_policies(): void
    {
        $catalog = $this->publish();
        $catalog['contact_email'] = null;
        $catalog['contact_text'] = null;
        config(['legal.catalog' => $catalog]);
        $this->getJson('/api/legal')->assertJsonPath('published', false);
    }

    public function test_explicit_registration_choices_are_validated_and_recorded_atomically(): void
    {
        $catalog = $this->publish();
        $payload = $this->registration() + ['legal_version' => $catalog['version'], 'terms_accepted' => false, 'privacy_acknowledged' => true];
        $this->postJson('/api/register', $payload)->assertUnprocessable()->assertJsonValidationErrors('terms_accepted');
        $this->assertSame(0, User::count());
        $payload['terms_accepted'] = true;
        $userId = $this->postJson('/api/register', $payload)->assertCreated()->json('user.USR_ID');
        $this->assertSame(2, LegalAcceptance::where('USR_ID', $userId)->count());
        $row = LegalAcceptance::where('DOCUMENT', 'terms')->firstOrFail();
        $this->assertSame('AGREED', $row->ACTION);
        $this->assertSame(hash('sha256', $row->CONTENT), $row->CONTENT_HASH);
        $this->assertSame('ACKNOWLEDGED', LegalAcceptance::where('DOCUMENT', 'privacy')->firstOrFail()->ACTION);
    }

    public function test_legal_acceptances_are_scoped_versioned_explicit_and_idempotent(): void
    {
        $catalog = $this->publish();
        $this->postJson('/api/legal/acceptances', [])->assertUnauthorized();
        $owner = $this->user();
        $other = $this->user();
        Sanctum::actingAs($owner);
        $payload = ['legal_version' => $catalog['version'], 'documents' => ['seller', 'verification'], 'accepted' => true, 'USR_ID' => $other->USR_ID, 'ACCEPTED_AT' => '2000-01-01'];
        $this->postJson('/api/legal/acceptances', array_merge($payload, ['accepted' => false]))->assertUnprocessable();
        $this->postJson('/api/legal/acceptances', array_merge($payload, ['legal_version' => 'old']))->assertUnprocessable();
        $this->postJson('/api/legal/acceptances', array_merge($payload, ['documents' => ['missing']]))->assertUnprocessable();
        $this->assertSame(0, LegalAcceptance::count());
        $this->postJson('/api/legal/acceptances', $payload)->assertOk();
        $first = LegalAcceptance::where('DOCUMENT', 'seller')->firstOrFail();
        $this->assertSame($owner->USR_ID, $first->USR_ID);
        $this->assertStringNotContainsString('2000-01-01', $first->ACCEPTED_AT);
        $this->travel(1)->hours();
        $this->postJson('/api/legal/acceptances', $payload)->assertOk();
        $this->assertSame(2, LegalAcceptance::count());
        $this->assertSame($first->ACCEPTED_AT, $first->fresh()->ACCEPTED_AT);
        $this->assertSame('CONSENTED', LegalAcceptance::where('DOCUMENT', 'verification')->firstOrFail()->ACTION);
        Sanctum::actingAs($other);
        $this->getJson('/api/legal/acceptances')->assertOk()->assertJsonCount(0, 'acceptances');
    }

    public function test_mobile_and_web_policies_are_identical_and_do_not_invent_contact_details(): void
    {
        $web = file_get_contents(resource_path('legal/policies.json'));
        $mobile = file_get_contents(base_path('../mobile/farmspot_app/assets/legal/policies.json'));
        $this->assertSame($web, $mobile);
        $catalog = app(LegalPolicies::class)->catalog();
        $this->assertFalse($catalog['published']);
        $this->assertNull($catalog['contact_email']);
    }
}
