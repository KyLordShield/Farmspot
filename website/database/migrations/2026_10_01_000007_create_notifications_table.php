<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a reporter be told what happened to their complaint.
 *
 * A report is a one-way door today: the buyer presses submit, hears nothing
 * ever, and cannot tell whether a moderator looked at it or whether reporting
 * is simply broken. That silence is the other half of why the queue felt
 * pointless — a moderator could act and the buyer would still be left guessing.
 *
 * This is Laravel's standard database-channel table so notify() and
 * $user->notifications work without custom plumbing. The one deviation from the
 * project schema is notifiable_id: this database uses char(6) ids throughout,
 * where morphs() would have created an unsignedBigInteger that cannot hold a
 * USR_ID.
 *
 * The app's inbox screen does not exist yet, so nothing displays this yet. The
 * data is written and readable now so the screen is a rendering job later
 * rather than a data-modelling job.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::dropIfExists('notifications');

        Schema::create('notifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('type');

            // Declared by hand rather than with morphs(), which would make
            // notifiable_id an unsignedBigInteger — too narrow for a char(6)
            // USR_ID in this schema.
            $table->string('notifiable_type');
            $table->char('notifiable_id', 6);
            $table->index(['notifiable_type', 'notifiable_id']);

            $table->text('data');
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notifications');
    }
};
