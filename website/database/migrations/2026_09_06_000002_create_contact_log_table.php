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
        Schema::create('contact_log', function (Blueprint $table) {
            $table->char('CTL_ID', 6)->collation('utf8mb4_general_ci');
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->char('LST_ID', 6)->collation('utf8mb4_general_ci');
            $table->enum('CTL_METHOD', ['CALL', 'SMS']);
            $table->dateTime('CTL_CREATED_AT');
            $table->primary('CTL_ID');
            $table->index('USR_ID', 'FK_CONTACTLOG_USER');
            $table->index('LST_ID', 'FK_CONTACTLOG_LISTING');
            $table->foreign('USR_ID')->references('USR_ID')->on('user')
                ->onDelete('cascade')->onUpdate('cascade');
            $table->foreign('LST_ID')->references('LST_ID')->on('listing')
                ->onDelete('cascade')->onUpdate('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('contact_log');
    }
};