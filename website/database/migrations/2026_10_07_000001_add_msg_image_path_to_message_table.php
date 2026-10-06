<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a message carry a photo as well as text.
 *
 * Text stays optional (the app can send an image-only message) and the photo
 * does, too (a plain text message is unchanged). MSG_CONTENT is NOT NULL by
 * table definition, so an image-only message stores an empty string there and
 * MSG_IMAGE_PATH holds the uploaded Cloudinary URL. Every consumer picks the
 * string when present and only then falls back to reading the text.
 *
 * varchar(500) matches the other file-path columns (USR_PHOTO_PATH,
 * LPHOTO_FILE_PATH) — Cloudinary URLs are well under that.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->string('MSG_IMAGE_PATH', 500)
                ->nullable()
                ->after('MSG_CONTENT');
        });
    }

    public function down(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->dropColumn('MSG_IMAGE_PATH');
        });
    }
};