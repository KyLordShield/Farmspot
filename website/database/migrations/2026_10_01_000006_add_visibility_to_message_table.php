<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a moderator act on a reported chat message.
 *
 * Until this, a MESSAGE report could be read and statused but never enforced:
 * there was no way to hide the message, so harassment the user reported stayed
 * on screen and stayed sendable. The page said as much, which was honest but
 * left the most-reported kind of abuse the least actionable.
 *
 * A visibility flag rather than a delete, for the same reason the rest of the
 * moderation flow is non-destructive — undo has to be possible, and the
 * conversation history has to stay auditable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->enum('MSG_VISIBILITY', ['VISIBLE', 'HIDDEN'])
                ->default('VISIBLE')
                ->after('MSG_CONTENT')
                ->comment('HIDDEN by a moderator after a report. Rows are kept so the action can be undone and the history stays auditable.');

            $table->dateTime('MSG_HIDDEN_AT')->nullable()->after('MSG_VISIBILITY')
                  ->comment('When it was hidden, for the audit trail.');
        });
    }

    public function down(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->dropColumn(['MSG_VISIBILITY', 'MSG_HIDDEN_AT']);
        });
    }
};
