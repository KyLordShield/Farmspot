<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('audit_log', function (Blueprint $table) {
            $table->dropForeign(Schema::getConnection()->getDriverName() === 'sqlite' ? ['USR_ID'] : 'FK_AUDITLOG_USER');
        });
        Schema::table('audit_log', function (Blueprint $table) {
            $actor = $table->char('USR_ID', 6)->nullable()->change();
            if (Schema::getConnection()->getDriverName() === 'mysql') {
                $actor->collation('utf8mb4_general_ci');
            }
            $table->string('AUD_ACTOR_NAME')->nullable();
            $table->string('AUD_TARGET_TYPE', 60)->nullable();
            $table->string('AUD_TARGET_ID', 100)->nullable();
            $table->string('AUD_ROUTE', 150)->nullable();
            $table->json('AUD_CHANGES')->nullable();
            $table->index(['AUD_CREATED_AT', 'AUD_ID'], 'audit_log_chronology');
            $table->foreign('USR_ID', 'FK_AUDITLOG_USER')->references('USR_ID')->on('user')->nullOnDelete()->cascadeOnUpdate();
        });
    }

    public function down(): void
    {
        // Keep nullable actors and retained history when rolling back the UI fields.
        Schema::table('audit_log', function (Blueprint $table) {
            $table->dropIndex('audit_log_chronology');
            $table->dropColumn(['AUD_ACTOR_NAME', 'AUD_TARGET_TYPE', 'AUD_TARGET_ID', 'AUD_ROUTE', 'AUD_CHANGES']);
        });
    }
};
