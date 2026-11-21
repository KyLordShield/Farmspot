<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('search_log', function (Blueprint $table) {
            $table->index(['SRCH_CREATED_AT', 'SRCH_KEYWORD', 'USR_ID'], 'search_log_insights_period_index');
        });
        Schema::create('insight_demo_searches', function (Blueprint $table) {
            $table->id();
            $table->string('batch', 40);
            $table->dateTime('searched_at');
            $table->string('crop', 200);
            $table->unsignedInteger('searcher');
            $table->index(['batch', 'searched_at', 'crop', 'searcher'], 'insight_demo_period_index');
        });
        Schema::create('insight_demo_listings', function (Blueprint $table) {
            $table->id();
            $table->string('batch', 40)->index();
            $table->string('crop', 200);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('insight_demo_listings');
        Schema::dropIfExists('insight_demo_searches');
        Schema::table('search_log', fn (Blueprint $table) => $table->dropIndex('search_log_insights_period_index'));
    }
};
