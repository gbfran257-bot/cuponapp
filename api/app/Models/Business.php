<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Business extends Model
{
    protected $fillable = [
        'name', 'active', 'admin_id', 'address', 'phone',
        'commission_product', 'commission_percent', 'commission_money',
        'contact_name', 'contact_email', 'rfc', 'description',
    ];

    protected $casts = [
        'active' => 'boolean',
        'commission_product' => 'decimal:2',
        'commission_percent' => 'decimal:2',
        'commission_money' => 'decimal:2',
    ];

    public function coupons()
    {
        return $this->hasMany(Coupon::class);
    }

    public function admin()
    {
        return $this->belongsTo(User::class, 'admin_id');
    }
}