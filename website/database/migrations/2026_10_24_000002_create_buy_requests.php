<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('buy_request', function (Blueprint $table) {
            $table->char('BRQ_ID', 6)->collation('utf8mb4_general_ci')->primary();
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->string('BRQ_CROP', 80);
            $table->decimal('BRQ_QUANTITY_KG', 10, 2);
            $table->string('BRQ_FREQUENCY', 20);
            $table->string('BRQ_PICKUP_LOCATION', 255)->nullable();
            $table->decimal('BRQ_LATITUDE', 5, 2)->nullable();
            $table->decimal('BRQ_LONGITUDE', 6, 2)->nullable();
            $table->text('BRQ_NOTE')->nullable();
            $table->dateTime('BRQ_CREATED_AT');
            $table->dateTime('BRQ_REMOVED_AT')->nullable();
            $table->index(['USR_ID', 'BRQ_REMOVED_AT']);
            $table->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
        });
        Schema::table('conversation', function (Blueprint $table) {
            $table->char('BRQ_ID', 6)->collation('utf8mb4_general_ci')->nullable();
            $table->foreign('BRQ_ID')->references('BRQ_ID')->on('buy_request')->nullOnDelete();
            $table->unique(['BRQ_ID', 'FMR_ID'], 'conversation_request_seller_unique');
        });
    }

    public function down(): void
    {
        Schema::table('conversation', function (Blueprint $table) {
            $table->dropForeign(['BRQ_ID']);
            $table->dropUnique('conversation_request_seller_unique');
            $table->dropColumn('BRQ_ID');
        });
        Schema::dropIfExists('buy_request');
    }
};
