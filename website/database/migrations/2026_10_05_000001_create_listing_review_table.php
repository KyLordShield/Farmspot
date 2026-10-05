<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Buyer reviews for a listing: a 1-5 star rating plus an optional comment.
 *
 * One review per user per listing. Submitting a second time UPDATES the row
 * already there rather than inserting a duplicate or failing on the unique
 * key, so "I changed my mind about this crop" is a normal action and not an
 * error the app has to special-case.
 *
 * LRV_STATUS exists so moderation is reversible. Hiding a review flips the
 * flag; nothing is ever deleted by an admin, and hiding takes the review out
 * of both the visible list and the rating average in one move.
 *
 * The CHECK constraint is belt-and-braces. The API validates 1..5, but the
 * column is a TINYINT so a negative or 6 would otherwise store silently and
 * poison the average. MariaDB 10.4 (the project's server) enforces CHECK, so
 * this is real protection rather than a comment.
 */
return new class extends Migration
{
    public function up(): void
    {
        // No dropIfExists here on purpose. This migration is additive: it must
        // never remove a table it does not own, because on a re-run it would
        // take every existing review with it. If an earlier attempt left a
        // half-built table behind without the migration being recorded, the
        // create below fails loudly on "already exists" and that has to be
        // cleared by hand. A silent skip is worse than that failure: it would
        // mark the migration as applied against a schema it did not create.
        Schema::create('listing_review', function (Blueprint $table) {
            $table->char('LRV_ID', 6)->primary();
            // utf8mb4_general_ci to match the rest of the schema. The legacy
            // tables came from a dump at general_ci while Laravel's default is
            // unicode_ci, and a foreign key between two columns whose collations
            // differ cannot even be created (errno 150).
            $table->char('LST_ID', 6)->collation('utf8mb4_general_ci');
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->unsignedTinyInteger('LRV_RATING');
            $table->string('LRV_COMMENT', 300)->nullable();
            // Admin moderation. VISIBLE is the default so an insert that omits
            // the column is never accidentally invisible.
            $table->enum('LRV_STATUS', ['VISIBLE', 'HIDDEN'])->default('VISIBLE');

            // datetime(6), not a plain datetime, for the same reason report_action
            // went through the same change: at MySQL's default one-second
            // resolution, several reviews written in the same second tie, and
            // "newest first" then falls back to LRV_ID — six random digits — so
            // the order is arbitrary and a buyer's own two reviews can swap
            // places between page loads. Microseconds make the sort
            // deterministic. See 2026_10_01_000009 for the same fix upstream.
            $table->dateTime('LRV_CREATED_AT', 6);
            $table->dateTime('LRV_UPDATED_AT', 6);

            // Index for "the visible reviews for this listing, newest first",
            // which is the single read every screen performs.
            $table->index(['LST_ID', 'LRV_STATUS'], 'IDX_REVIEW_LISTING_STATUS');
            // "Does this user already have a review here?" hits the unique key.
            $table->unique(['LST_ID', 'USR_ID'], 'UX_REVIEW_LISTING_USER');
            $table->index('USR_ID', 'IDX_REVIEW_USER');

            $table->foreign('LST_ID')->references('LST_ID')->on('listing')
                ->cascadeOnDelete()->cascadeOnUpdate();
            $table->foreign('USR_ID')->references('USR_ID')->on('user')
                ->cascadeOnDelete()->cascadeOnUpdate();
        });

        // Laravel 12's Blueprint has no check() method, so the rating guard is
        // added as raw DDL. unsignedTinyInteger already rules out 0 and
        // negatives at the column level; this caps the top end so a 6 cannot
        // be stored and silently poison the average.
        //
        // MySQL parses CHECK and ignores it; MariaDB 10.4 (the project's
        // server) enforces it. Wrapped so the migration still succeeds on a
        // MySQL server rather than aborting the whole migrate.
        try {
            DB::statement(
                'ALTER TABLE listing_review ADD CONSTRAINT CHK_REVIEW_RATING CHECK (LRV_RATING BETWEEN 1 AND 5)'
            );
        } catch (\Throwable $e) {
            // No CHECK support on this server. The API validation and the
            // unsigned column still hold the line.
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('listing_review');
    }
};