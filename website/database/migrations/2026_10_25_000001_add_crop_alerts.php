<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const EXISTING_TYPES = [
        'LISTING_EXPIRING_SOON',
        'LISTING_EXPIRED',
        'LISTING_REMOVED',
        'SELLER_DEACTIVATED',
        'ACCOUNT_SUSPENDED',
        'ACCOUNT_REACTIVATED',
        'REPORT_UPDATE',
        'HARVEST_REMINDER',
        'SETUP_COMPLETE',
        'WHITELIST_APPROVED',
        'SELLER_REACTIVATED',
        'FARM_REJECTED',
        'LISTING_AVAILABLE',
        'APPEAL_APPROVED',
        'APPEAL_DENIED',
        'SAVED_FARM_NEW_LISTING',
        'SAVED_FARM_AVAILABLE',
        'BUY_REQUEST_MATCH',
    ];

    public function up(): void
    {
        Schema::table('premium_alert_setting', function (Blueprint $table) {
            $table->boolean('CROP_ALERTS')->default(true);
            $table->json('ALERT_CROPS')->nullable();
        });
        $this->types([...self::EXISTING_TYPES, 'CROP_AVAILABLE']);
    }

    public function down(): void
    {
        DB::table('notification')->where('NOTIF_TYPE', 'CROP_AVAILABLE')->delete();
        $this->types(self::EXISTING_TYPES);
        Schema::table('premium_alert_setting', fn (Blueprint $table) => $table->dropColumn(['CROP_ALERTS', 'ALERT_CROPS']));
    }

    private function types(array $types): void
    {
        DB::statement("ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('".implode("','", $types)."') NOT NULL");
    }
};
