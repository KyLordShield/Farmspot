<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('saved_farm', function (Blueprint $table) {
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->char('FRM_ID', 6)->collation('utf8mb4_general_ci');
            $table->dateTime('SAVED_AT');
            $table->primary(['USR_ID', 'FRM_ID']);
            $table->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
            $table->foreign('FRM_ID')->references('FRM_ID')->on('farm')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('saved_farm');
    }
};
