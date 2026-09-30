<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Add the ARCHIVED state to the farm status enum.
     *
     * Archiving is a SOFT delete: the farm row, its photos, its listings and
     * every buyer conversation that referenced it are left untouched. We only
     * flip FRM_STATUS to ARCHIVED and FRM_PIN_ACTIVE to 0, which is enough to
     * drop the farm off the public map (mapPins filters on APPROVED + pin
     * active) and out of the seller's farm switcher (index filters on APPROVED
     * / PENDING_REVIEW).
     *
     * A hard delete is deliberately NOT used. conversation.FRM_ID,
     * contact_log and farm_visit_log are all ON DELETE CASCADE from farm, so
     * deleting the farm would silently destroy the seller's buyer message
     * history and contact records.
     */
    public function up(): void
    {
        DB::statement("ALTER TABLE `farm` MODIFY `FRM_STATUS` ENUM('PENDING_REVIEW','APPROVED','REJECTED','ARCHIVED') NOT NULL DEFAULT 'PENDING_REVIEW'");
    }

    /**
     * Reverse the migrations.
     *
     * Rows already archived have to be moved back to a surviving state first,
     * otherwise the narrower enum cannot hold their value.
     */
    public function down(): void
    {
        DB::statement("UPDATE `farm` SET `FRM_STATUS` = 'REJECTED' WHERE `FRM_STATUS` = 'ARCHIVED'");
        DB::statement("ALTER TABLE `farm` MODIFY `FRM_STATUS` ENUM('PENDING_REVIEW','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING_REVIEW'");
    }
};
