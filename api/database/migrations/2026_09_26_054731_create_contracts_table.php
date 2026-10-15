<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('contracts', function (Blueprint $table) {
            $table->id();

            $table->foreignId('business_id')
                ->constrained('businesses')
                ->cascadeOnDelete();

            $table->foreignId('admin_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->string('contract_number', 50)->unique();
            $table->string('status', 30)->default('pending_admin')->index();

            // Snapshot del negocio al momento de generar el convenio.
            $table->string('business_name', 150);
            $table->string('contact_name', 150)->nullable();
            $table->string('contact_email', 150)->nullable();
            $table->string('rfc', 13)->nullable();
            $table->string('address', 255)->nullable();
            $table->string('phone', 20)->nullable();
            $table->decimal('commission_product', 12, 2)->default(0);
            $table->decimal('commission_percent', 12, 2)->default(0);
            $table->decimal('commission_money', 12, 2)->default(0);
            $table->text('description')->nullable();

            // Documento generado y su hash para identificar la versión aceptada.
            $table->string('pdf_path')->nullable();
            $table->string('document_hash', 64)->nullable();

            // Aceptación/firma electrónica del administrador.
            $table->foreignId('admin_signed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->string('admin_signed_name', 150)->nullable();
            $table->string('admin_signed_email', 150)->nullable();
            $table->timestamp('admin_signed_at')->nullable();
            $table->string('admin_signed_ip', 45)->nullable();

            // Aceptación/firma electrónica del súper administrador.
            $table->foreignId('super_signed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->string('super_signed_name', 150)->nullable();
            $table->string('super_signed_email', 150)->nullable();
            $table->timestamp('super_signed_at')->nullable();
            $table->string('super_signed_ip', 45)->nullable();

            $table->timestamps();

            $table->index(['business_id', 'admin_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('contracts');
    }
};
