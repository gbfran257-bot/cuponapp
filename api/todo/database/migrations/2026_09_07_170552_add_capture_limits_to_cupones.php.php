<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('coupons', function (Blueprint $table) {
            $table->unsignedInteger('max_captures')
                ->default(1)
                ->after('active');

            $table->unsignedInteger('captures_count')
                ->default(0)
                ->after('max_captures');
        });
    }

    public function down(): void
    {
        Schema::table('coupons', function (Blueprint $table) {
            $table->dropColumn([
                'max_captures',
                'captures_count',
            ]);
        });
    }
};