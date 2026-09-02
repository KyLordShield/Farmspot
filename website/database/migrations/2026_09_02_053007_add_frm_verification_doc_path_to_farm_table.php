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
            $table->string('FRM_VERIFICATION_DOC_PATH', 500)
                ->nullable()
                ->after('FRM_CREATED_AT');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('farm', function (Blueprint $table) {
            $table->dropColumn('FRM_VERIFICATION_DOC_PATH');
        });
    }
};
