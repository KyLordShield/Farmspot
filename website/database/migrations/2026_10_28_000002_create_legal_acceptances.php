<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('legal_acceptances', function (Blueprint $table) {
            $table->uuid('ID')->primary();
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->string('DOCUMENT', 32);
            $table->string('VERSION', 40);
            $table->char('CONTENT_HASH', 64);
            $table->longText('CONTENT');
            $table->string('ACTION', 16);
            $table->dateTime('ACCEPTED_AT');
            $table->unique(['USR_ID', 'DOCUMENT', 'VERSION']);
            $table->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('legal_acceptances');
    }
};
