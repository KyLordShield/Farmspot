<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('listing_photo', function (Blueprint $table) {
            $table->char('LPHOTO_ID', 6)->collation('utf8mb4_general_ci');
            $table->string('LPHOTO_FILE_PATH', 500)->collation('utf8mb4_general_ci');
            $table->dateTime('LPHOTO_UPLOADED_AT');
            $table->boolean('LPHOTO_IS_PRIMARY')->default(0);
            $table->char('LST_ID', 6)->collation('utf8mb4_general_ci');
            $table->primary('LPHOTO_ID');
            $table->index('LST_ID', 'FK_LISTINGPHOTO_LISTING');
            $table->foreign('LST_ID')->references('LST_ID')->on('listing')
                ->onDelete('cascade')->onUpdate('cascade');
        });

        // Backfill: every listing that already has an LST_IMAGE gets a single
        // primary listing_photo row holding that same URL, so the existing
        // single-image data becomes the seed of the new gallery.
        DB::table('listing')
            ->whereNotNull('LST_IMAGE')
            ->where('LST_IMAGE', '<>', '')
            ->orderBy('LST_ID')
            ->chunk(200, function ($listings) {
                foreach ($listings as $listing) {
                    DB::table('listing_photo')->insert([
                        'LPHOTO_ID' => $this->uniqueId(),
                        'LPHOTO_FILE_PATH' => $listing->LST_IMAGE,
                        'LPHOTO_UPLOADED_AT' => $listing->LST_CREATED_AT ?? now(),
                        'LPHOTO_IS_PRIMARY' => 1,
                        'LST_ID' => $listing->LST_ID,
                    ]);
                }
            });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('listing_photo');
    }

    private function uniqueId(): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table('listing_photo')->where('LPHOTO_ID', $id)->exists());

        return $id;
    }
};
