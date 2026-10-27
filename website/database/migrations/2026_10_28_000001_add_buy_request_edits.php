<?php

use App\Models\UserNotification;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('buy_request', fn (Blueprint $table) => $table->dateTime('BRQ_UPDATED_AT')->nullable());
        Schema::table('notification', fn (Blueprint $table) => $table->string('NOTIF_DEDUP_KEY', 80)->nullable()->unique());
        if (DB::getDriverName() === 'mysql') {
            $types = array_unique([...UserNotification::TYPES, 'APPEAL_APPROVED', 'APPEAL_DENIED']);
            DB::statement("ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('".implode("','", $types)."') NOT NULL");
        }
    }

    public function down(): void
    {
        Schema::table('notification', fn (Blueprint $table) => $table->dropColumn('NOTIF_DEDUP_KEY'));
        Schema::table('buy_request', fn (Blueprint $table) => $table->dropColumn('BRQ_UPDATED_AT'));
    }
};
