<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CouponCapture extends Model
{
    protected $fillable = [
        'coupon_id',
        'user_id',
        'photo_path',
        'latitude',
        'longitude',
        'distance_meters',
        'captured_at',
    ];

    protected $casts = [
        'captured_at' => 'datetime',
        'latitude' => 'float',
        'longitude' => 'float',
        'distance_meters' => 'float',
    ];

    public function coupon()
    {
        return $this->belongsTo(Coupon::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}