<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Password reset for the mobile app, by emailed code.
 *
 * Deliberately NOT Laravel's `password_reset_tokens` (added 2026_10_06), even
 * though that table now sits unused in this schema. Four reasons:
 *
 *   1. That table is keyed on `email`. Every other table here keys on USR_ID,
 *      and a USR_ID foreign key is the only thing that can cascade correctly
 *      when a user is deleted.
 *   2. It has no attempt counter. A 6-digit code is ~1e6 combinations, which is
 *      brute-forceable in minutes without a lockout. A link token is 60 random
 *      characters and never needs one. This is the single most important
 *      difference between the two designs.
 *   3. It has no explicit expiry column - expiry is inferred from created_at
 *      plus a config value, which cannot be per-row once a code is issued.
 *   4. It cannot express "this code was already used", so a replayed code
 *      stays valid for the whole window.
 *
 * Storing the CODE_HASH rather than the code means a leaked database row is not
 * a set of working reset codes: there are only 1e6 candidates and bcrypt makes
 * each one expensive to test. Storing the code in plaintext would make this
 * table a password-equivalent.
 *
 * Primary key is USR_ID, not an auto-increment: one live code per user is a
 * rule we want the database to enforce. Asking for a second code silently
 * replaces the first, which is exactly the behaviour we want on a "resend"
 * button and exactly what we do NOT want from two concurrent requests.
 */
return new class extends Migration
{
    public function up(): void
    {
        // A failed earlier run can leave the table behind without the migration
        // being recorded, which then makes every retry fail on "already exists".
        Schema::dropIfExists('PASSWORD_RESET_CODE');

        Schema::create('PASSWORD_RESET_CODE', function (Blueprint $table) {
            // utf8mb4_general_ci to match the legacy dump. The user table came
            // from that dump at general_ci while Laravel's default is
            // unicode_ci, and a foreign key between two columns whose collations
            // differ cannot be created at all (errno 150).
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci')
                ->comment('User the code was issued to; one live code per user');

            // 60 is exactly a bcrypt hash length. The 6-digit code is never
            // stored, only this hash of it.
            $table->string('RSTC_CODE_HASH', 60)
                ->comment('bcrypt hash of the 6-digit code, never the code itself');

            $table->dateTime('RSTC_EXPIRES_AT')
                ->comment('When the code stops being accepted');

            $table->tinyInteger('RSTC_ATTEMPTS')->default(0)
                ->comment('Failed verification attempts; locks the code out once it hits the cap');

            $table->dateTime('RSTC_CONSUMED_AT')->nullable()
                ->comment('Set the moment the code is successfully used, so it cannot be replayed');

            $table->dateTime('RSTC_CREATED_AT')
                ->comment('When the code was issued');

            $table->primary('USR_ID');

            $table->foreign('USR_ID', 'FK_RESET_CODE_USER')->references('USR_ID')->on('user')
                ->onDelete('cascade')->onUpdate('cascade');

            // Lets the cleanup command find expired codes without scanning the
            // whole table on every request.
            $table->index('RSTC_EXPIRES_AT', 'IDX_RESET_CODE_EXPIRES');
        });

        // Note: the "only GENERAL_USER may hold a reset code" rule is enforced in
        // the controller, not here. MySQL forbids subqueries inside a CHECK
        // constraint, so a role test against `user` cannot be expressed at the
        // schema level at all. The FK above is the strongest guarantee the
        // engine can give us.
    }

    public function down(): void
    {
        Schema::dropIfExists('PASSWORD_RESET_CODE');
    }
};