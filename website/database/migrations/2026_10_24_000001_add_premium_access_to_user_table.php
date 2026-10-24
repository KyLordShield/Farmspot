<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->dateTime('USR_PREMIUM_STARTED_AT')->nullable();
            $table->dateTime('USR_PREMIUM_EXPIRES_AT')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->dropColumn(['USR_PREMIUM_STARTED_AT', 'USR_PREMIUM_EXPIRES_AT']);
        });
    }
};
