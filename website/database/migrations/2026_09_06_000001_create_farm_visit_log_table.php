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
        Schema::create('farm_visit_log', function (Blueprint $table) {
            $table->char('FVL_ID', 6)->collation('utf8mb4_general_ci');
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->char('FRM_ID', 6)->collation('utf8mb4_general_ci');
            $table->dateTime('FVL_CREATED_AT');
            $table->primary('FVL_ID');
            $table->index('USR_ID', 'FK_FARMVISITLOG_USER');
            $table->index('FRM_ID', 'FK_FARMVISITLOG_FARM');
            $table->foreign('USR_ID')->references('USR_ID')->on('user')
                ->onDelete('cascade')->onUpdate('cascade');
            $table->foreign('FRM_ID')->references('FRM_ID')->on('farm')
                ->onDelete('cascade')->onUpdate('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('farm_visit_log');
    }
};