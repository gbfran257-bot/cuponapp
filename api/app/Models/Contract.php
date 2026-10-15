<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Contract extends Model
{
    protected $fillable = [
        'business_id',
        'admin_id',
        'contract_number',
        'status',
        'business_name',
        'contact_name',
        'contact_email',
        'rfc',
        'address',
        'phone',
        'commission_product',
        'commission_percent',
        'commission_money',
        'description',
        'pdf_path',
        'document_hash',
        'admin_signed_by',
        'admin_signed_name',
        'admin_signed_email',
        'admin_signed_at',
        'admin_signed_ip',
        'super_signed_by',
        'super_signed_name',
        'super_signed_email',
        'super_signed_at',
        'super_signed_ip',
    ];

    protected $casts = [
        'commission_product' => 'decimal:2',
        'commission_percent' => 'decimal:2',
        'commission_money' => 'decimal:2',
        'admin_signed_at' => 'datetime',
        'super_signed_at' => 'datetime',
    ];

    public function business(): BelongsTo
    {
        return $this->belongsTo(Business::class);
    }

    public function admin(): BelongsTo
    {
        return $this->belongsTo(User::class, 'admin_id');
    }

    public function adminSigner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'admin_signed_by');
    }

    public function superSigner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'super_signed_by');
    }
}
