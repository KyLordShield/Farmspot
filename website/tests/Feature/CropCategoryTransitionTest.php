<?php

namespace Tests\Feature;

use App\Services\CropCategorySuggestion;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class CropCategoryTransitionTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:']);
        DB::purge('sqlite');
        Schema::create('crop_category', function (Blueprint $table) {
            $table->string('CAT_ID')->primary();
            $table->string('CAT_NAME')->unique();
            $table->string('CAT_ICON')->nullable();
            $table->string('CAT_DESCRIPTION')->nullable();
        });
        foreach (['listing' => 'LST_ID', 'insight' => 'INS_ID', 'trend' => 'TRND_ID'] as $table => $primary) {
            Schema::create($table, function (Blueprint $table) use ($primary) {
                $table->string($primary)->primary();
                $table->string('CAT_ID')->nullable()->references('CAT_ID')->on('crop_category');
                $table->string('LST_CROP_ICON')->nullable();
                $table->string('UNCHANGED')->default('preserve this');
            });
        }
        DB::table('crop_category')->insert([
            ['CAT_ID' => 'FRTVEG', 'CAT_NAME' => 'Fruit Vegetables'],
            ['CAT_ID' => 'LEAFVG', 'CAT_NAME' => 'Leafy Vegetables'],
            ['CAT_ID' => 'LEGMES', 'CAT_NAME' => 'Legumes'],
            ['CAT_ID' => 'HRBSPC', 'CAT_NAME' => 'Herbs & Spices'],
            ['CAT_ID' => 'ROOTCP', 'CAT_NAME' => 'Root Crops'],
        ]);
    }

    public function test_migration_preserves_listings_and_reports_and_can_restore_original_links(): void
    {
        DB::table('listing')->insert([
            ['LST_ID' => 'LST001', 'CAT_ID' => 'FRTVEG', 'LST_CROP_ICON' => 'Kamatis'],
            ['LST_ID' => 'LST002', 'CAT_ID' => 'LEGMES', 'LST_CROP_ICON' => 'Bataw'],
            ['LST_ID' => 'LST003', 'CAT_ID' => 'FRTVEG', 'LST_CROP_ICON' => 'Screen-Test Crop'],
            ['LST_ID' => 'LST004', 'CAT_ID' => 'FRTVEG', 'LST_CROP_ICON' => 'Sili Spada'],
        ]);
        DB::table('insight')->insert(['INS_ID' => 'INS001', 'CAT_ID' => 'LEGMES']);
        DB::table('trend')->insert(['TRND_ID' => 'TRN001', 'CAT_ID' => 'FRTVEG']);
        $migration = require database_path('migrations/2026_10_27_000002_simplify_crop_categories.php');
        $migration->up();
        $this->assertDatabaseCount('crop_category', 6);
        $this->assertDatabaseCount('listing', 4);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'CAT_ID' => 'LEAFVG', 'UNCHANGED' => 'preserve this']);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST002', 'CAT_ID' => 'LEAFVG']);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST003', 'CAT_ID' => 'OTHERS']);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST004', 'CAT_ID' => 'HRBSPC']);
        $this->assertDatabaseHas('insight', ['INS_ID' => 'INS001', 'CAT_ID' => 'LEAFVG', 'UNCHANGED' => 'preserve this']);
        $this->assertDatabaseHas('trend', ['TRND_ID' => 'TRN001', 'CAT_ID' => 'LEAFVG']);
        DB::table('listing')->insert(['LST_ID' => 'NEW001', 'CAT_ID' => 'FRUITS', 'LST_CROP_ICON' => 'Mango']);
        $migration->down();
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'CAT_ID' => 'FRTVEG']);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST002', 'CAT_ID' => 'LEGMES']);
        $this->assertDatabaseHas('insight', ['INS_ID' => 'INS001', 'CAT_ID' => 'LEGMES']);
        $this->assertDatabaseHas('trend', ['TRND_ID' => 'TRN001', 'CAT_ID' => 'FRTVEG']);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'NEW001', 'CAT_ID' => 'FRUITS']);
        $this->assertDatabaseHas('crop_category', ['CAT_ID' => 'FRUITS']);
    }

    public function test_common_crops_and_local_aliases_are_classified_without_guessing_unknown_words(): void
    {
        $service = app(CropCategorySuggestion::class);
        foreach (['Tomato' => 'LEAFVG', ' TOMATOES! ' => 'LEAFVG', 'Kamatis' => 'LEAFVG',
            'bataw' => 'LEAFVG', 'Hyacinth beans' => 'LEAFVG', 'kamote' => 'ROOTCP',
            'luya' => 'HRBSPC', 'sili spada' => 'HRBSPC', 'mangga' => 'FRUITS', 'mais' => 'GRAINS'] as $crop => $id) {
            $this->assertSame($id, $service->suggest($crop), $crop);
        }
        $this->assertNull($service->suggest('new unknown variety'));
        $this->assertNull($service->suggest(''));
        $this->assertSame('FRUITS', $service->suggest('Apple fresh 50kg'));
        $this->assertSame('LEAFVG', $service->suggest('Cabbage Cheap For Sale'));
        $this->assertSame('ROOTCP', $service->suggest('Sweet potatoes fresh 10kg'));
        $this->assertNull($service->suggest('Apple and cabbage bundle'));
        $this->assertNull($service->suggest('Applewood timber'));
        $this->assertSame('FRUITS', $service->suggest('Pineapple fresh'));
        $this->assertContains('Tomatoes', array_map('ucfirst', $service->aliases('LEAFVG')));
    }
}
