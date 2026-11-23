<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const TABLES = ['whitelist', 'notifications'];

    private function backupPath(): string
    {
        return storage_path('app/private/database-backups/2026_11_24_legacy_tables_'.hash('sha256', DB::connection()->getDatabaseName()).'.json');
    }

    public function up(): void
    {
        $path = $this->backupPath();
        $backup = File::exists($path) ? json_decode(File::get($path), true, 512, JSON_THROW_ON_ERROR) : [];
        foreach (self::TABLES as $table) {
            if (! Schema::hasTable($table)) {
                continue;
            }
            if (DB::getDriverName() === 'mysql') {
                $definition = array_values((array) DB::selectOne('SHOW CREATE TABLE `'.$table.'`'))[1];
            } elseif (DB::getDriverName() === 'sqlite') {
                $definition = DB::selectOne("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [$table])->sql;
            } else {
                throw new RuntimeException('Unsupported database driver for legacy table backup.');
            }
            $backup[$table] = ['schema' => $definition, 'rows' => DB::table($table)->get()->map(fn ($row) => (array) $row)->all()];
        }
        // Complete and verify the private backup before performing any DDL.
        File::ensureDirectoryExists(dirname($path), 0700);
        $json = json_encode($backup, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR);
        if (File::put($path, $json, true) !== strlen($json) || File::get($path) !== $json) {
            throw new RuntimeException('Legacy table backup could not be verified; no tables were removed.');
        }
        foreach (self::TABLES as $table) {
            Schema::dropIfExists($table);
        }
    }

    public function down(): void
    {
        $path = $this->backupPath();
        if (! File::exists($path)) {
            throw new RuntimeException('Restore the private legacy-table backup before rolling back this migration.');
        }
        $backup = json_decode(File::get($path), true, 512, JSON_THROW_ON_ERROR);
        foreach (self::TABLES as $table) {
            if (! isset($backup[$table]) || Schema::hasTable($table)) {
                continue;
            }
            DB::statement($backup[$table]['schema']);
            foreach (array_chunk($backup[$table]['rows'], 100) as $rows) {
                DB::table($table)->insert($rows);
            }
        }
    }
};
