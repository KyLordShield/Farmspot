<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('premium_checkout', function (Blueprint $t) {
            $t->uuid('ID')->primary();
            $userId = $t->char('USR_ID', 6);
            if (Schema::getConnection()->getDriverName() === 'mysql') {
                $userId->collation('utf8mb4_general_ci');
            }
            $t->string('SESSION_ID', 100)->nullable()->unique();
            $t->string('PAYMENT_ID', 100)->nullable()->unique();
            $t->text('CHECKOUT_URL')->nullable();
            $t->json('CREATE_PAYLOAD');
            $t->unsignedInteger('AMOUNT');
            $t->string('CURRENCY', 3);
            $t->string('STATUS', 20)->default('CREATING');
            $t->dateTime('CREATED_AT');
            $t->dateTime('UPDATED_AT');
            $t->dateTime('PAID_AT')->nullable();
            $t->dateTime('PREMIUM_UNTIL')->nullable();
            $t->foreign('USR_ID')->references('USR_ID')->on('user')->cascadeOnDelete();
            $t->index(['USR_ID', 'STATUS']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('premium_checkout');
    }
};
