<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The password-reset token store.
 *
 * Laravel's password broker reads and writes this table by name, so the table
 * and column names here are the framework's own and must not be renamed to
 * match the custom PWD_ / USR_ convention the rest of the schema uses:
 * Illuminate\Auth\Passwords\DatabaseTokenRepository looks for
 * `password_reset_tokens` with `email`, `token` and `created_at`.
 *
 * This table was never created anywhere else. The core tables in this project
 * come from database/schema/mysql-schema.sql, which predates Laravel's Breeze
 * install and does not include it, so `Password::sendResetLink()` failed with
 * "Base table or view not found" whenever an admin asked for a reset link.
 *
 * `email` is the primary key because the broker looks a token up by address and
 * only needs the newest row per address; tokens for an address are overwritten
 * on each request, so a single row per address is correct rather than a
 * limitation.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('password_reset_tokens')) {
            return;
        }

        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('password_reset_tokens');
    }
};