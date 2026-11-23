<?php

namespace Tests\Feature;

use App\Http\Middleware\RecordAdminChanges;
use App\Models\AdminPlanner;
use App\Models\AuditLog;
use App\Models\CropCategory;
use App\Models\User;
use App\Services\AdminMfa;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class AdminAuditTest extends TestCase
{
    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:']);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $t) {
            $t->char('USR_ID', 6)->primary();
            $t->string('USR_NAME');
            $t->string('USR_EMAIL');
            $t->string('USR_PASSWORD');
            $t->string('USR_ROLE');
            $t->string('USR_STATUS');
        });
        Schema::create('audit_log', function (Blueprint $t) {
            $t->char('AUD_ID', 6)->primary();
            $t->string('AUD_ACTION', 100);
            $t->text('AUD_DETAILS')->nullable();
            $t->dateTime('AUD_CREATED_AT');
            $t->char('USR_ID', 6);
            $t->foreign('USR_ID', 'FK_AUDITLOG_USER')->references('USR_ID')->on('user')->cascadeOnDelete();
        });
        (require database_path('migrations/2026_11_23_000001_extend_admin_audit_log.php'))->up();
        Schema::create('crop_category', function (Blueprint $t) {
            $t->char('CAT_ID', 6)->primary();
            $t->string('CAT_NAME')->unique();
            $t->string('CAT_ICON')->nullable();
            $t->string('CAT_DESCRIPTION')->nullable();
        });
        foreach (['listing', 'insight', 'trend'] as $table) {
            Schema::create($table, function (Blueprint $t) {
                $t->char('CAT_ID', 6);
            });
        }
        Schema::create('admin_planner', function (Blueprint $t) {
            $t->char('APL_ID', 6)->primary();
            $t->char('USR_ID', 6);
            $t->string('APL_TYPE');
            $t->string('APL_TITLE');
            $t->text('APL_BODY')->nullable();
            $t->dateTime('APL_DATETIME')->nullable();
            $t->boolean('APL_IS_DONE')->default(false);
            $t->boolean('APL_NOTIFY_FARMERS')->default(false);
            $t->dateTime('APL_CREATED_AT');
            $t->dateTime('APL_UPDATED_AT')->nullable();
        });
        $this->admin = User::create([
            'USR_ID' => 'ADMIN1', 'USR_NAME' => 'Test Admin', 'USR_EMAIL' => 'admin@example.test',
            'USR_PASSWORD' => bcrypt('password'), 'USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'ACTIVE',
        ]);
        CropCategory::create(['CAT_ID' => 'CAT001', 'CAT_NAME' => 'Vegetables', 'CAT_ICON' => 'eco']);
        $this->signIn();
    }

    private function signIn(): void
    {
        $this->actingAs($this->admin)->withSession(['admin_mfa' => [
            'verified' => app(AdminMfa::class)->fingerprint($this->admin),
            'started' => now()->timestamp, 'last_seen' => now()->timestamp,
        ]]);
    }

    public function test_real_admin_category_edits_record_before_after_and_skip_noops_and_validation_errors(): void
    {
        $data = ['CAT_NAME' => 'Fresh vegetables', 'CAT_ICON' => 'eco'];
        $this->put('/categories/CAT001', $data)->assertRedirect();
        $log = AuditLog::sole();
        $this->assertSame('ADMIN1', $log->USR_ID);
        $this->assertSame('Test Admin', $log->AUD_ACTOR_NAME);
        $this->assertSame('CAT001', $log->AUD_TARGET_ID);
        $this->assertSame(['before' => 'Vegetables', 'after' => 'Fresh vegetables'], $log->AUD_CHANGES['CAT_NAME']);
        $this->put('/categories/CAT001', $data)->assertRedirect();
        $this->put('/categories/CAT001', ['CAT_NAME' => ''])->assertSessionHasErrors('CAT_NAME');
        $this->assertSame(1, AuditLog::count());
    }

    public function test_category_creation_and_deletion_are_recorded(): void
    {
        $this->post('/categories', ['CAT_NAME' => 'Fruit', 'CAT_ICON' => 'spa'])->assertRedirect();
        $category = CropCategory::where('CAT_NAME', 'Fruit')->sole();
        $this->assertDatabaseHas('audit_log', ['AUD_ACTION' => 'CROP_CATEGORY_CREATED', 'AUD_TARGET_ID' => $category->CAT_ID]);
        $this->delete('/categories/'.$category->CAT_ID)->assertRedirect();
        $this->assertDatabaseHas('audit_log', ['AUD_ACTION' => 'CROP_CATEGORY_DELETED', 'AUD_TARGET_ID' => $category->CAT_ID]);
    }

    public function test_rolled_back_changes_are_not_audited_and_query_updates_of_route_target_are_recorded(): void
    {
        Route::middleware(['web', 'auth', RecordAdminChanges::class])->put('/audit-test/{id}', function ($id) {
            try {
                DB::transaction(function () use ($id) {
                    CropCategory::findOrFail($id)->update(['CAT_NAME' => 'Rolled back']);
                    throw new \RuntimeException('rollback');
                });
            } catch (\RuntimeException) {
                return response()->noContent();
            }
        })->name('categories.rollback');
        $this->put('/audit-test/CAT001')->assertNoContent();
        $this->assertSame(0, AuditLog::count());

        Route::middleware(['web', 'auth', RecordAdminChanges::class])->put('/audit-bulk/{id}', function ($id) {
            CropCategory::whereKey($id)->update(['CAT_NAME' => 'Bulk edit']);
            return response()->noContent();
        })->name('categories.bulk');
        $this->put('/audit-bulk/CAT001')->assertNoContent();
        $this->assertSame('Bulk edit', AuditLog::sole()->AUD_CHANGES['CAT_NAME']['after']);
    }

    public function test_password_and_private_planner_content_are_redacted(): void
    {
        Route::middleware(['web', 'auth', RecordAdminChanges::class])->post('/audit-private', function () {
            User::findOrFail('ADMIN1')->update(['USR_PASSWORD' => bcrypt('secret-new-password')]);
            AdminPlanner::create(['APL_ID' => 'NOTE01', 'USR_ID' => 'ADMIN1', 'APL_TYPE' => 'NOTE', 'APL_TITLE' => 'Private title', 'APL_BODY' => 'Private body', 'APL_CREATED_AT' => now()]);
            return response()->noContent();
        });
        $this->post('/audit-private')->assertNoContent();
        $this->assertSame(2, AuditLog::count());
        $raw = AuditLog::all()->toJson();
        $this->assertStringNotContainsString('secret-new-password', $raw);
        $this->assertStringNotContainsString('Private title', $raw);
        $this->assertStringNotContainsString('Private body', $raw);
        $this->assertStringContainsString('[redacted]', $raw);
    }

    public function test_history_is_searchable_and_restricted_to_verified_administrators(): void
    {
        AuditLog::record('OLD_ACTION', 'Historical entry', 'ADMIN1');
        $this->put('/categories/CAT001', ['CAT_NAME' => 'Fresh vegetables', 'CAT_ICON' => 'eco'])->assertRedirect();
        $this->get('/audit-log')->assertOk()->assertSee('Historical entry')->assertSee('Fresh vegetables');
        $this->get('/audit-log?search=CAT001')->assertOk()->assertDontSee('Historical entry')->assertSee('Fresh vegetables');
        $this->get('/audit-log?from=2000-01-01&to=2000-01-02')->assertOk()->assertSee('No recorded changes');

        $this->actingAs(new User(['USR_ID' => 'BUY001', 'USR_ROLE' => 'GENERAL_USER']))->get('/audit-log')->assertForbidden();
        $this->app['auth']->forgetGuards();
        $this->get('/audit-log')->assertRedirect(route('login'));
        $this->actingAs($this->admin)->withSession(['admin_mfa' => []])->get('/audit-log')->assertRedirect(route('login'));
    }

    public function test_deleting_an_actor_keeps_existing_history(): void
    {
        AuditLog::record('HISTORICAL_ACTION', 'Kept for accountability', 'ADMIN1', ['actor_name' => 'Test Admin']);
        $this->admin->delete();
        $this->assertSame(1, AuditLog::count());
        $this->assertNull(AuditLog::sole()->USR_ID);
        $this->assertSame('Test Admin', AuditLog::sole()->AUD_ACTOR_NAME);
    }

    public function test_large_change_batches_render_in_separate_modals_with_escaped_values(): void
    {
        $changes = [];
        for ($i = 0; $i < 40; $i++) {
            $changes['FIELD_'.$i] = ['before' => false, 'after' => str_repeat('LongValue', 200).'<script>alert(1)</script>'];
        }
        foreach (['CAT001', 'CAT002'] as $id) {
            AuditLog::record('CATEGORY_UPDATED', 'Batch update', 'ADMIN1', [
                'target_id' => $id, 'changes' => $changes,
            ]);
        }
        $response = $this->get('/audit-log')->assertOk();
        $html = $response->getContent();
        $this->assertStringNotContainsString('<script>alert(1)</script>', $html);
        $this->assertStringContainsString('&lt;script&gt;alert(1)&lt;/script&gt;', $html);

        $dom = new \DOMDocument();
        @$dom->loadHTML('<?xml encoding="utf-8" ?>'.$html);
        $xpath = new \DOMXPath($dom);
        $this->assertSame(0, $xpath->query('//table//details | //table//div[contains(@class,"audit-change-modal")]')->length);
        $this->assertSame(2, $xpath->query('//div[contains(@class,"audit-change-modal")]')->length);
        $this->assertSame(80, $xpath->query('//section[contains(@class,"audit-change-card")]')->length);
        foreach (AuditLog::all() as $log) {
            $this->assertSame(1, $xpath->query('//*[@id="audit-changes-'.$log->AUD_ID.'"]')->length);
            $this->assertSame(1, $xpath->query('//button[@data-bs-target="#audit-changes-'.$log->AUD_ID.'"]')->length);
        }
    }

    public function test_seller_documents_are_proxied_only_for_verified_administrators(): void
    {
        Schema::create('farm', function (Blueprint $table) {
            $table->char('FRM_ID', 6)->primary();
            $table->text('FRM_VERIFICATION_DOC_PATH')->nullable();
            $table->text('FRM_FARM_CERTIFICATE_PATH')->nullable();
        });
        DB::table('farm')->insert(['FRM_ID' => 'FARM01', 'FRM_VERIFICATION_DOC_PATH' => 'https://res.cloudinary.com/demo/image/upload/id.jpg', 'FRM_FARM_CERTIFICATE_PATH' => 'https://res.cloudinary.com/demo/image/upload/permit.pdf']);
        \Illuminate\Support\Facades\Http::fake([
            '*id.jpg' => \Illuminate\Support\Facades\Http::response('image bytes', 200, ['Content-Type' => 'image/jpeg']),
            '*permit.pdf' => \Illuminate\Support\Facades\Http::response('%PDF-test', 200, ['Content-Type' => 'application/pdf']),
        ]);
        $this->get('/seller-requests/FARM01/documents/id')->assertOk()->assertContent('image bytes')->assertHeader('Content-Type', 'image/jpeg');
        $this->get('/seller-requests/FARM01/documents/permit')->assertOk()->assertContent('%PDF-test')->assertHeader('X-Frame-Options', 'SAMEORIGIN');
        DB::table('farm')->where('FRM_ID', 'FARM01')->update(['FRM_VERIFICATION_DOC_PATH' => 'http://127.0.0.1/private']);
        $this->get('/seller-requests/FARM01/documents/id')->assertNotFound();
        $this->get('/seller-requests/FARM01/documents/other')->assertNotFound();
        $this->actingAs(new User(['USR_ID' => 'BUY001', 'USR_ROLE' => 'GENERAL_USER']))->get('/seller-requests/FARM01/documents/permit')->assertForbidden();
        $this->actingAs($this->admin)->withSession(['admin_mfa' => []])->get('/seller-requests/FARM01/documents/permit')->assertRedirect(route('login'));
        $this->app['auth']->forgetGuards();
        $this->get('/seller-requests/FARM01/documents/permit')->assertRedirect(route('login'));
    }
}
