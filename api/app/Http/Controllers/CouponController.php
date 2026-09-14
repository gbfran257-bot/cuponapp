<?php

namespace App\Http\Controllers;

use App\Models\Business;
use App\Models\Category;
use App\Models\Coupon;
use App\Models\CouponCapture;
use App\Models\Redemption;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class CouponController extends Controller
{
    // GET /api/coupons -> activos, para la app del usuario final
    public function index(Request $request)
    {
        $user = $request->user();

        $query = Coupon::with('category')->where('active', true);

        if ($request->filled('category')) {
            $categoryName = $request->query('category');
            $query->whereHas('category', fn ($q) => $q->where('name', $categoryName));
        }

        $coupons = $query->get();

        if ($request->filled('latitude') && $request->filled('longitude')) {
            $lat = (float) $request->query('latitude');
            $lng = (float) $request->query('longitude');

            $coupons = $coupons->sortBy(function ($c) use ($lat, $lng) {
                if ($c->latitude === null || $c->longitude === null) {
                    return PHP_FLOAT_MAX;
                }
                return $this->distanceKm($lat, $lng, $c->latitude, $c->longitude);
            })->values();
        }

        return response()->json($coupons->map(fn ($c) => $this->formatForUser($c, $user)));
    }

    // GET /api/coupons/mine -> cupones que el usuario ya capturó
    public function mine(Request $request)
    {
        $user = $request->user();

        $couponIds = CouponCapture::where('user_id', $user->id)
            ->pluck('coupon_id')
            ->unique();

        $coupons = Coupon::with('category')
            ->whereIn('id', $couponIds)
            ->orderByDesc('id')
            ->get();

        return response()->json($coupons->map(fn ($c) => $this->formatForUser($c, $user)));
    }

    // POST /api/coupons/capture (multipart: token_id, latitude, longitude, photo)
    public function capture(Request $request)
    {
        $data = $request->validate([
            'token_id' => 'required|string',
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'photo' => 'required|image|max:6144',
        ]);

        $coupon = Coupon::where('token_id', $data['token_id'])->first();

        if (!$coupon) {
            return response()->json(['message' => 'Cupón no encontrado'], 404);
        }

        if (!$coupon->active) {
            return response()->json(['message' => 'Este cupón ya no está activo'], 422);
        }

        $user = $request->user();

        // Un usuario solo puede capturar un cupón dado una vez
        // (restricción única coupon_id + user_id en la tabla).
        $alreadyCaptured = CouponCapture::where('coupon_id', $coupon->id)
            ->where('user_id', $user->id)
            ->exists();

        if ($alreadyCaptured) {
            return response()->json([
                'message' => 'Ya capturaste este cupón anteriormente',
            ], 422);
        }

        // Cupo GLOBAL compartido entre todos los usuarios.
        if ($coupon->captures_count >= $coupon->max_captures) {
            return response()->json([
                'message' => 'Este cupón ya alcanzó el máximo de capturas disponibles',
            ], 422);
        }

        $photoPath = null;
        if ($request->hasFile('photo')) {
            $path = $request->file('photo')->store('captures', 'public');
            $photoPath = asset('storage/' . $path);
        }

        CouponCapture::create([
            'coupon_id' => $coupon->id,
            'user_id' => $user->id,
            'photo_path' => $photoPath,
            'latitude' => $data['latitude'],
            'longitude' => $data['longitude'],
            'captured_at' => now(),
        ]);

        $coupon->increment('captures_count');

        return response()->json([
            'message' => 'Cupón capturado correctamente',
            'coupon' => $this->formatForUser($coupon->fresh('category'), $user),
        ]);
    }

    // GET /api/admin/coupons -> todos, para el panel de administrador
    public function adminIndex()
    {
        $coupons = Coupon::with('category')
            ->orderByDesc('id')
            ->get()
            ->map(fn ($c) => $this->format($c));

        return response()->json($coupons);
    }

    // POST /api/admin/coupons  (multipart/form-data)
    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:150',
            'business' => 'required|string|max:150',
            'discount' => 'required|string|max:30',
            'expires_at' => 'required|date',
            'category' => 'required|string',
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'photo' => 'nullable|image|max:4096',
            'token_id' => 'nullable|string|max:20|unique:coupons,token_id',
        ]);

        $category = Category::firstOrCreate(['name' => $data['category']]);
        $business = Business::firstOrCreate(
            ['name' => $data['business']],
            ['active' => true]
        );

        $photoUrl = null;
        if ($request->hasFile('photo')) {
            $path = $request->file('photo')->store('coupons', 'public');
            $photoUrl = asset('storage/' . $path);
        }

        $coupon = Coupon::create([
            'token_id' => $data['token_id'] ?? ('TKN-' . strtoupper(Str::random(6))),
            'name' => $data['name'],
            'business' => $business->name,
            'business_id' => $business->id,
            'discount' => $data['discount'],
            'expires_at' => $data['expires_at'],
            'category_id' => $category->id,
            'photo_url' => $photoUrl,
            'latitude' => $data['latitude'],
            'longitude' => $data['longitude'],
            'created_by' => $request->user()->id,
        ]);

        return response()->json($this->format($coupon->load('category')), 201);
    }

    // PUT /api/admin/coupons/{id}
    public function update(Request $request, $id)
    {
        $coupon = Coupon::findOrFail($id);

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:150',
            'business' => 'sometimes|required|string|max:150',
            'discount' => 'sometimes|required|string|max:30',
            'expires_at' => 'sometimes|required|date',
            'category' => 'sometimes|required|string',
            'latitude' => 'sometimes|required|numeric',
            'longitude' => 'sometimes|required|numeric',
            'photo' => 'nullable|image|max:4096',
        ]);

        if (isset($data['category'])) {
            $category = Category::firstOrCreate(['name' => $data['category']]);
            $coupon->category_id = $category->id;
        }

        if (isset($data['business'])) {
            $business = Business::firstOrCreate(
                ['name' => $data['business']],
                ['active' => true]
            );
            $coupon->business_id = $business->id;
            $coupon->business = $business->name;
        }

        if ($request->hasFile('photo')) {
            $path = $request->file('photo')->store('coupons', 'public');
            $coupon->photo_url = asset('storage/' . $path);
        }

        $coupon->fill(collect($data)->except(['category', 'business', 'photo'])->toArray());
        $coupon->save();

        return response()->json($this->format($coupon->load('category')));
    }

    // PATCH /api/admin/coupons/{id}/status
    public function toggleStatus($id)
    {
        $coupon = Coupon::findOrFail($id);
        $coupon->active = !$coupon->active;
        $coupon->save();

        return response()->json($this->format($coupon->load('category')));
    }

    // DELETE /api/admin/coupons/{id}
    public function destroy($id)
    {
        Coupon::findOrFail($id)->delete();
        return response()->json(['message' => 'Cupón eliminado']);
    }

    // POST /api/coupons/redeem  (uso del ADMINISTRADOR al escanear/cobrar)
    public function redeem(Request $request)
    {
        $request->validate(['code' => 'required|string']);
        $code = trim($request->code);

        $coupon = Coupon::where('token_id', $code)
            ->orWhere('id', str_replace(['C-', 'c-'], '', $code))
            ->first();

        if (!$coupon) {
            return response()->json(['message' => 'Código no encontrado'], 404);
        }

        if (!$coupon->active) {
            return response()->json(['message' => 'Ese cupón está dado de baja'], 422);
        }

        Redemption::create([
            'coupon_id' => $coupon->id,
            'redeemed_by' => $request->user()?->id,
            'redeemed_at' => now(),
        ]);

        return response()->json([
            'message' => 'Cupón canjeado',
            'coupon' => $this->format($coupon),
        ]);
    }

    private function distanceKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadius = 6371;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
        return $earthRadius * $c;
    }

    private function format(Coupon $c): array
    {
        return [
            'id' => 'C-' . str_pad((string) $c->id, 3, '0', STR_PAD_LEFT),
            'numericId' => (string) $c->id,
            'tokenId' => $c->token_id,
            'name' => $c->name,
            'business' => $c->business,
            'discount' => $c->discount,
            'expiresAt' => $c->expires_at?->format('d/m/Y'),
            'expiresAtIso' => $c->expires_at?->format('Y-m-d'),
            'category' => $c->category->name ?? 'Otro',
            'photoUrl' => $c->photo_url,
            'latitude' => $c->latitude,
            'longitude' => $c->longitude,
            'active' => $c->active,
        ];
    }

        private function formatForUser(Coupon $c, $user): array
    {
        // "¿Ya lo capturé yo?" — determina si el botón sigue
        // disponible PARA ESTE usuario (aunque queden cupos
        // globales, si él ya lo capturó no puede repetir).
        $alreadyCaptured = $user
            ? CouponCapture::where('coupon_id', $c->id)->where('user_id', $user->id)->exists()
            : false;

        $max = $c->max_captures ?? 1;
        $capturesCount = $c->captures_count ?? 0;
        $remaining = max(0, $max - $capturesCount);

        return array_merge($this->format($c), [
            'maxCaptures' => $max,
            'capturesCount' => $capturesCount,
            'remainingCaptures' => $remaining,
            'captureAvailable' => $remaining > 0 && !$alreadyCaptured,
            'alreadyCaptured' => $alreadyCaptured,
        ]);
    }
}