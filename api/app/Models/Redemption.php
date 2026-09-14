<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Redemption extends Model
{
    public $timestamps = false;

    protected $fillable = ['coupon_id', 'redeemed_by', 'redeemed_at'];

    protected $casts = [
        'redeemed_at' => 'datetime',
    ];

    public function coupon()
    {
        return $this->belongsTo(Coupon::class);
    }
}