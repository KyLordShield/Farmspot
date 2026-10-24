<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('buy_request', function (Blueprint $table) {
            $table->boolean('BRQ_HAS_PIN')->default(false);
            $table->decimal('BRQ_LATITUDE', 10, 7)->nullable()->change();
            $table->decimal('BRQ_LONGITUDE', 11, 7)->nullable()->change();
        });
        // Old approximate locations are not relabelled as precise map pins.
    }

    public function down(): void
    {
        Schema::table('buy_request', function (Blueprint $table) {
            $table->dropColumn('BRQ_HAS_PIN');
            // Keep the wider coordinates: rollback must not round saved pins.
        });
    }
};
