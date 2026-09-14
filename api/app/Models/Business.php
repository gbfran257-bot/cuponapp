<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Business extends Model
{
    protected $fillable = ['name', 'active'];

    protected $casts = [
        'active' => 'boolean',
    ];

    public function coupons()
    {
        return $this->hasMany(Coupon::class);
    }
}