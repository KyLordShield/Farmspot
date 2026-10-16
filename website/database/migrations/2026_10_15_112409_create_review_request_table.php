<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A request to look again at a listing or an account that was taken down.
 *
 * This is the "I was reported and taken down but I did nothing wrong" path. It
 * is deliberately keyed to the TAKEDOWN, not to any single report: an admin can
 * take something down without a report ever being filed, and that owner is just
 * as entitled to contest it.
 *
 *   - RRQ_TARGET_TYPE is LISTING or USER. A listing row points at an LST_ID, an
 *     account row at a USR_ID. A farmer-deleted listing has no takedown reason,
 *     so it is never appealable and never appears here.
 *   - USR_ID is the person who filed the appeal, always the owner of the target.
 *     An account appeal is filed by the owner after login was refused, which is
 *     why the account endpoint re-checks their email and password: the row must
 *     belong to the real owner, not to anyone who guessed the target id.
 *   - RRQ_STATUS is PENDING until a moderator decides. One pending appeal per
 *     target is enforced in the controller; a DENIED appeal stays denied until a
 *     NEW takedown happens (compared against the target's *_TAKEDOWN_AT).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('review_request', function (Blueprint $table) {
            // utf8mb4_general_ci on every char column, not Laravel's default
            // utf8mb4_unicode_ci. These columns hold the same six-character ids
            // as the legacy tables, which came from a dump at general_ci, and a
            // foreign key between two columns whose collations differ cannot
            // even be created (errno 150). Matching them also keeps an equality
            // lookup such as RRQ_TARGET_ID = LST_ID able to use its index.
            $table->char('RRQ_ID', 6)->collation('utf8mb4_general_ci')->primary();
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->enum('RRQ_TARGET_TYPE', ['LISTING', 'USER']);
            $table->char('RRQ_TARGET_ID', 6)->collation('utf8mb4_general_ci');
            $table->text('RRQ_REASON')->nullable();
            $table->text('RRQ_ADMIN_NOTE')->nullable();
            $table->enum('RRQ_STATUS', ['PENDING', 'APPROVED', 'DENIED'])->default('PENDING');
            $table->char('RRQ_DECIDED_BY', 6)->collation('utf8mb4_general_ci')->nullable();
            $table->datetime('RRQ_CREATED_AT');
            $table->datetime('RRQ_DECIDED_AT')->nullable();

            $table->index('USR_ID');
            $table->index(['RRQ_TARGET_TYPE', 'RRQ_TARGET_ID']);
            $table->index('RRQ_STATUS');

            $table->foreign('USR_ID')->references('USR_ID')->on('user')
                ->onDelete('cascade')->onUpdate('cascade');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('review_request');
    }
};
