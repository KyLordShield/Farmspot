<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->string('USR_ADDRESS', 255)
                ->nullable()
                ->after('USR_MOBILE_NUMBER');
            $table->string('USR_PHOTO_PATH', 500)
                ->nullable()
                ->after('USR_ADDRESS');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->dropColumn(['USR_ADDRESS', 'USR_PHOTO_PATH']);
        });
    }
};