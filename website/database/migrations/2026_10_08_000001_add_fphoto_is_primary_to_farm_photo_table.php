<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('farm_photo', function (Blueprint $table) {
            $table->boolean('FPHOTO_IS_PRIMARY')->default(0);
        });

        // Backfill: give every farm that already has photos exactly one cover —
        // its oldest photo. Same rule the farm UI now enforces (adding a new
        // photo only marks it primary when the farm has none), so the data that
        // predates the column and the behaviour that follows it agree.
        DB::table('farm_photo')
            ->select('FRM_ID')
            ->distinct()
            ->get()
            ->each(function ($farm) {
                $oldest = DB::table('farm_photo')
                    ->where('FRM_ID', $farm->FRM_ID)
                    ->orderBy('FPHOTO_UPLOADED_AT')
                    ->orderBy('FPHOTO_ID')
                    ->first();

                if ($oldest) {
                    DB::table('farm_photo')
                        ->where('FPHOTO_ID', $oldest->FPHOTO_ID)
                        ->update(['FPHOTO_IS_PRIMARY' => 1]);
                }
            });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('farm_photo', function (Blueprint $table) {
            $table->dropColumn('FPHOTO_IS_PRIMARY');
        });
    }
};