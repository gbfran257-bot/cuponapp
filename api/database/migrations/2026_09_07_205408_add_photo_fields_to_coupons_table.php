<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        /*
         * admin_id
         *
         * Esta columna identifica al administrador
         * que creó el cupón.
         */
        if (!Schema::hasColumn('coupons', 'admin_id')) {
            Schema::table('coupons', function (Blueprint $table) {
                $table->foreignId('admin_id')
                    ->nullable()
                    ->after('id')
                    ->constrained('users')
                    ->nullOnDelete();
            });
        }

        /*
         * photo_path
         *
         * Tu base de datos YA tiene esta columna,
         * por eso solamente la creamos si no existe.
         */
        if (!Schema::hasColumn('coupons', 'photo_path')) {
            Schema::table('coupons', function (Blueprint $table) {
                $table->string('photo_path')
                    ->nullable()
                    ->after('longitude');
            });
        }

        /*
         * photo_url
         *
         * La creamos solamente si todavía no existe.
         */
        if (!Schema::hasColumn('coupons', 'photo_url')) {
            Schema::table('coupons', function (Blueprint $table) {
                $table->string('photo_url')
                    ->nullable()
                    ->after('photo_path');
            });
        }
    }

    public function down(): void
    {
        /*
         * Eliminamos únicamente lo que corresponda.
         */

        if (Schema::hasColumn('coupons', 'admin_id')) {
            Schema::table('coupons', function (Blueprint $table) {
                $table->dropForeign([
                    'admin_id',
                ]);

                $table->dropColumn('admin_id');
            });
        }

        /*
         * NO eliminamos photo_path aquí porque esa columna
         * ya existía antes de esta migración.
         *
         * photo_url sí puede haber sido creada por esta
         * migración, pero para evitar borrar datos existentes
         * también la dejamos intacta.
         */
    }
};