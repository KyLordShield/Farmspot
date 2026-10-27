<?php

use App\Services\CropCategorySuggestion;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const LINKS = ['listing' => 'LST_ID', 'insight' => 'INS_ID', 'trend' => 'TRND_ID'];

    public function up(): void
    {
        Schema::create('crop_category_change_backup', function (Blueprint $table) {
            $table->string('KIND', 20);
            $table->string('RECORD_ID', 64);
            $table->json('DATA');
            $table->primary(['KIND', 'RECORD_ID']);
        });
        DB::transaction(function () {
            $old = DB::table('crop_category')->get();
            foreach ($old as $category) {
                DB::table('crop_category_change_backup')->insert(['KIND' => 'category', 'RECORD_ID' => $category->CAT_ID, 'DATA' => json_encode($category)]);
                // Release unique names before assigning the canonical IDs.
                DB::table('crop_category')->where('CAT_ID', $category->CAT_ID)->update(['CAT_NAME' => 'Migrating '.$category->CAT_ID]);
            }
            foreach (config('crop_categories') as $id => $category) {
                DB::table('crop_category')->updateOrInsert(['CAT_ID' => $id], ['CAT_NAME' => $category['name'], 'CAT_ICON' => $category['icon'], 'CAT_DESCRIPTION' => $category['description']]);
            }
            foreach (self::LINKS as $table => $primary) {
                DB::table($table)->whereNotNull('CAT_ID')->orderBy($primary)->chunkById(500, function ($rows) use ($table, $primary) {
                    foreach ($rows as $row) {
                        DB::table('crop_category_change_backup')->insert(['KIND' => $table, 'RECORD_ID' => $row->$primary, 'DATA' => json_encode(['CAT_ID' => $row->CAT_ID])]);
                        if ($table === 'listing') {
                            $target = app(CropCategorySuggestion::class)->suggest($row->LST_CROP_ICON) ?? 'OTHERS';
                        } else {
                            $target = in_array($row->CAT_ID, ['FRTVEG', 'LEGMES', 'LEAFVG']) ? 'LEAFVG' : (array_key_exists($row->CAT_ID, config('crop_categories')) ? $row->CAT_ID : 'OTHERS');
                        }
                        DB::table($table)->where($primary, $row->$primary)->update(['CAT_ID' => $target]);
                    }
                }, $primary);
            }
            DB::table('crop_category')->whereNotIn('CAT_ID', array_keys(config('crop_categories')))->delete();
        });
    }

    public function down(): void
    {
        DB::transaction(function () {
            $originals = DB::table('crop_category_change_backup')->where('KIND', 'category')->get();
            foreach ($originals as $row) {
                DB::table('crop_category')->updateOrInsert(['CAT_ID' => $row->RECORD_ID], json_decode($row->DATA, true));
            }
            foreach (self::LINKS as $table => $primary) {
                DB::table('crop_category_change_backup')->where('KIND', $table)->orderBy('RECORD_ID')->chunk(500, function ($rows) use ($table, $primary) {
                    foreach ($rows as $row) {
                        DB::table($table)->where($primary, $row->RECORD_ID)->update(json_decode($row->DATA, true));
                    }
                });
            }
            // Keep any new category already used by listings created since the
            // migration. A rollback must never orphan newer user data.
            foreach (array_diff(array_keys(config('crop_categories')), $originals->pluck('RECORD_ID')->all()) as $id) {
                $used = false;
                foreach (self::LINKS as $table => $primary) {
                    $used = $used || DB::table($table)->where('CAT_ID', $id)->exists();
                }
                if (! $used) {
                    DB::table('crop_category')->where('CAT_ID', $id)->delete();
                }
            }
        });
        Schema::dropIfExists('crop_category_change_backup');
    }
};
