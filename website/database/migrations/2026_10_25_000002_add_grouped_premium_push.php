<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('premium_alert_setting', function (Blueprint $t) {
            $t->boolean('PUSH_ENABLED')->default(false);
            $t->string('PUSH_FREQUENCY', 10)->default('hourly');
            $t->boolean('QUIET_ENABLED')->default(true);
            $t->string('QUIET_START', 5)->default('22:00');
            $t->string('QUIET_END', 5)->default('07:00');
            $t->string('DAILY_TIME', 5)->default('09:00');
        });
        Schema::create('premium_push_batch', function (Blueprint $t) {
            $t->uuid('ID')->primary();
            $t->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $t->string('MODE', 10);
            $t->string('GROUP_KEY', 120);
            $t->string('TITLE', 100);
            $t->string('BODY', 300);
            $t->dateTime('CREATED_AT');
            $t->dateTime('SENT_AT')->nullable();
            $t->dateTime('CANCELLED_AT')->nullable();
            $t->dateTime('NEXT_ATTEMPT_AT');
            $t->unsignedInteger('ATTEMPTS')->default(0);
            $t->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
            $t->index(['USR_ID', 'SENT_AT', 'CANCELLED_AT']);
        });
        Schema::create('premium_push_event', function (Blueprint $t) {
            $t->char('EVENT_KEY', 64)->primary();
            $t->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $t->string('TYPE', 40);
            $t->char('REF_ID', 6);
            $t->string('CROP', 100);
            $t->string('GROUP_KEY', 120);
            $t->uuid('BATCH_ID')->nullable();
            $t->dateTime('CREATED_AT');
            $t->dateTime('HANDLED_AT')->nullable();
            $t->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
            $t->foreign('BATCH_ID')->references('ID')->on('premium_push_batch')->nullOnDelete();
            $t->index(['USR_ID', 'HANDLED_AT', 'BATCH_ID']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('premium_push_event');
        Schema::dropIfExists('premium_push_batch');
        Schema::table('premium_alert_setting', fn (Blueprint $t) => $t->dropColumn(['PUSH_ENABLED', 'PUSH_FREQUENCY', 'QUIET_ENABLED', 'QUIET_START', 'QUIET_END', 'DAILY_TIME']));
    }
};
