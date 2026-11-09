<?php

use App\Models\UserNotification;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'mysql') {
            $types = array_unique([...UserNotification::TYPES, 'APPEAL_APPROVED', 'APPEAL_DENIED']);
            DB::statement("ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('".implode("','", $types)."') NOT NULL");
        }
    }

    public function down(): void
    {
        // Preserve delivered notifications when rolling back.
    }
};
