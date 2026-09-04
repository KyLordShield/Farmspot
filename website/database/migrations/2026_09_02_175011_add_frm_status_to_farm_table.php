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
        Schema::table('farm', function (Blueprint $table) {
            $table->enum('FRM_STATUS', ['PENDING_REVIEW', 'APPROVED', 'REJECTED'])
                ->default('PENDING_REVIEW')
                ->after('FRM_PIN_ACTIVE');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('farm', function (Blueprint $table) {
            $table->dropColumn('FRM_STATUS');
        });
    }
};
