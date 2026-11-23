<?php

namespace Tests\Feature;

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class LegacyTableCleanupTest extends TestCase
{
    public function test_cleanup_preserves_active_inbox_and_can_restore_legacy_data(): void
    {
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:']);
        DB::purge('sqlite');
        foreach (['whitelist', 'notifications', 'notification'] as $table) {
            Schema::create($table, function (Blueprint $table) {
                $table->string('id')->primary();
                $table->text('value');
            });
            DB::table($table)->insert(['id' => 'test', 'value' => 'Preserve this data']);
        }
        $storage = storage_path();
        $temporary = $storage.'/framework/testing/legacy-cleanup-'.uniqid();
        $this->app->useStoragePath($temporary);
        try {
            $migration = require database_path('migrations/2026_11_24_000001_remove_unused_legacy_tables.php');
            $migration->up();
            $this->assertFalse(Schema::hasTable('whitelist'));
            $this->assertFalse(Schema::hasTable('notifications'));
            $this->assertDatabaseHas('notification', ['id' => 'test', 'value' => 'Preserve this data']);
            $migration->up(); // A retry must not overwrite the original backup.
            $migration->down();
            foreach (['whitelist', 'notifications'] as $table) {
                $this->assertDatabaseHas($table, ['id' => 'test', 'value' => 'Preserve this data']);
            }
        } finally {
            $this->app->useStoragePath($storage);
            File::deleteDirectory($temporary);
        }
    }
}
