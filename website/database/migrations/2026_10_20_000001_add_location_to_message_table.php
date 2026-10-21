<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a seller share a pin in the chat.
 *
 * The coordinates are stored on the message itself rather than as a separate
 * "location" row: a shared location is just another thing a message can carry,
 * exactly like a photo. A message may have text as well (a caption), but the
 * coordinates are the part the recipient taps to open the map.
 *
 * decimal(10,7) is the precision the map needs (~1 cm) and the range the app
 * validates against (-90..90, -180..180). The label is optional; when it is
 * empty the app shows "Shared location".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->decimal('MSG_LATITUDE', 10, 7)
                ->nullable()
                ->after('MSG_IMAGE_PATH');
            $table->decimal('MSG_LONGITUDE', 10, 7)
                ->nullable()
                ->after('MSG_LATITUDE');
            $table->string('MSG_LOCATION_LABEL', 255)
                ->nullable()
                ->after('MSG_LONGITUDE');
        });
    }

    public function down(): void
    {
        Schema::table('message', function (Blueprint $table) {
            $table->dropColumn([
                'MSG_LATITUDE',
                'MSG_LONGITUDE',
                'MSG_LOCATION_LABEL',
            ]);
        });
    }
};
