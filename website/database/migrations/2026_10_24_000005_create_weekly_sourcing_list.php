<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('weekly_sourcing_list', function (Blueprint $table) {
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci')->primary();
            $table->json('CROPS');
            $table->dateTime('UPDATED_AT');
            $table->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('weekly_sourcing_list');
    }
};
