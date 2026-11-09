<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('premium_checkout', function (Blueprint $table) {
            $table->boolean('IS_LIVE')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('premium_checkout', function (Blueprint $table) {
            $table->dropColumn('IS_LIVE');
        });
    }
};
