<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('coupon_captures', function (Blueprint $table) {
            $table->id();

            $table->foreignId('coupon_id')
                ->constrained('coupons')
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->string('photo_path');

            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);

            $table->decimal('distance_meters', 10, 2)
                ->nullable();

            $table->timestamp('captured_at');

            $table->timestamps();

            /*
             * Un usuario solamente puede capturar
             * un cupón una vez.
             */
            $table->unique([
                'coupon_id',
                'user_id',
            ]);

            $table->index([
                'user_id',
                'created_at',
            ]);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coupon_captures');
    }
};