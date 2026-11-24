<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Imported Windows schemas already use lowercase. Fresh Linux installs
        // may have the uppercase table from the original migration. Rename it
        // in place so pending codes and their foreign keys are preserved.
        if (! Schema::hasTable('password_reset_code') && Schema::hasTable('PASSWORD_RESET_CODE')) {
            Schema::rename('PASSWORD_RESET_CODE', 'password_reset_code');
        }
    }

    public function down(): void
    {
        // Preserve the canonical table and its data on application rollback.
    }
};
