<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->text('USR_MFA_SECRET')->nullable();
            $table->unsignedBigInteger('USR_MFA_LAST_STEP')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->dropColumn(['USR_MFA_SECRET', 'USR_MFA_LAST_STEP']);
        });
    }
};
