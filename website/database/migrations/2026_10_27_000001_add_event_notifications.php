<?php

use App\Models\UserNotification;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('admin_planner', fn (Blueprint $table) => $table->boolean('APL_NOTIFY_FARMERS')->default(false));
        Schema::create('event_notice', function (Blueprint $table) {
            $table->uuid('ID')->primary();
            $table->char('APL_ID', 6)->unique();
            $table->string('TITLE', 150);
            $table->string('BODY', 300);
            $table->char('CURSOR', 6)->default('');
            $table->dateTime('CREATED_AT');
            $table->dateTime('FINISHED_AT')->nullable();
            $table->dateTime('CANCELLED_AT')->nullable();
            $table->index(['CANCELLED_AT', 'FINISHED_AT', 'CREATED_AT'], 'event_notice_pending');
        });
        Schema::create('event_notice_batch', function (Blueprint $table) {
            $table->uuid('ID')->primary();
            $table->uuid('NOTICE_ID')->index();
            $table->json('USERS');
            $table->string('STATE', 12)->default('pending');
            $table->unsignedTinyInteger('ATTEMPTS')->default(0);
            $table->dateTime('NEXT_AT');
            $table->dateTime('LEASE_UNTIL')->nullable();
            $table->dateTime('CREATED_AT');
            $table->dateTime('SENT_AT')->nullable();
            $table->index(['STATE', 'NEXT_AT'], 'event_batch_pending');
        });
        if (DB::getDriverName() === 'mysql') {
            $types = [...UserNotification::TYPES, 'APPEAL_APPROVED', 'APPEAL_DENIED'];
            DB::statement("ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('".implode("','", array_unique($types))."') NOT NULL");
        }
    }

    public function down(): void
    {
        // Keep the enum value on rollback so already-delivered inbox rows survive.
        Schema::dropIfExists('event_notice_batch');
        Schema::dropIfExists('event_notice');
        Schema::table('admin_planner', fn (Blueprint $table) => $table->dropColumn('APL_NOTIFY_FARMERS'));
    }
};
