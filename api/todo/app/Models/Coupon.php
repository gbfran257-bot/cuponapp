<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Coupon extends Model
{
    protected $fillable = [
        'token_id',
        'name',
        'business',
        'business_id',
        'discount',
        'expires_at',
        'category_id',
        'photo_url',
        'latitude',
        'longitude',
        'active',
        'max_captures',
        'captures_count',
        'created_by',
    ];

    protected $casts = [
        'active' => 'boolean',
        'expires_at' => 'date:Y-m-d',
        'latitude' => 'float',
        'longitude' => 'float',
        'max_captures' => 'integer',
        'captures_count' => 'integer',
    ];

    public function category()
    {
        return $this->belongsTo(Category::class);
    }

    public function businessRecord()
    {
        return $this->belongsTo(Business::class, 'business_id');
    }

    public function captures()
    {
        return $this->hasMany(CouponCapture::class);
    }
}