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
    ];

    private const NEW_TYPES = ['SAVED_FARM_NEW_LISTING', 'SAVED_FARM_AVAILABLE', 'BUY_REQUEST_MATCH'];

    public function up(): void
    {
        Schema::create('premium_alert_setting', function (Blueprint $table) {
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci')->primary();
            $table->boolean('ALERTS_ENABLED')->default(true);
            $table->boolean('SAVED_FARM_ALERTS')->default(true);
            $table->boolean('BUY_REQUEST_ALERTS')->default(true);
            $table->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
        });
        Schema::create('premium_alert_delivery', function (Blueprint $table) {
            $table->char('DELIVERY_KEY', 64)->primary();
            $table->char('USR_ID', 6)->collation('utf8mb4_general_ci');
            $table->dateTime('CREATED_AT');
            $table->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
        });
        $this->types([...self::EXISTING_TYPES, ...self::NEW_TYPES]);
    }

    public function down(): void
    {
        DB::table('notification')->whereIn('NOTIF_TYPE', self::NEW_TYPES)->delete();
        $this->types(self::EXISTING_TYPES);
        Schema::dropIfExists('premium_alert_delivery');
        Schema::dropIfExists('premium_alert_setting');
    }

    private function types(array $types): void
    {
        DB::statement("ALTER TABLE `notification` MODIFY `NOTIF_TYPE` ENUM('".implode("','", $types)."') NOT NULL");
    }
};
