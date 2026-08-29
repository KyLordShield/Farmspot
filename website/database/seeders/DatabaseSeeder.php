<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        User::create([
            'USR_ID' => strtoupper(Str::random(6)),
            'USR_NAME' => 'FarmSpot Admin',
            'USR_EMAIL' => 'admin@farmspot.test',
            'USR_PASSWORD' => Hash::make('Admin2026'),
            'USR_MOBILE_NUMBER' => '09171234567',
            'USR_ROLE' => 'ADMIN',
            'USR_IS_SELLER' => 0,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }
}