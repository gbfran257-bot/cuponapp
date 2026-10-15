<?php

namespace App\Http\Controllers;

use App\Models\Business;
use App\Models\Category;
use App\Models\Coupon;
use App\Models\CouponCapture;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class CouponController extends Controller
{
    // GET /api/coupons -> activos y vigentes, para la app del usuario final
    public function index(Request $request)
    {
        $user = $request->user();

        $query = Coupon::with('category')
            ->where('active', true)
            ->where(function ($q) {
                $q->whereNull('expires_at')
                    ->orWhereDate('expires_at', '>=', now()->toDateString());
            });

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

        // Una sola consulta para saber cuáles ya capturó este usuario
        // (antes era una consulta por cupón).
        $capturedIds = $user
            ? CouponCapture::where('user_id', $user->id)->pluck('coupon_id')->all()
            : [];

        return response()->json(
            $coupons->map(fn ($c) => $this->formatForUser($c, $capturedIds))
        );
    }

    // GET /api/coupons/mine -> cupones que el usuario ya capturó, con el
    // código de canje de SU captura y si ya lo usó.
    public function mine(Request $request)
    {
        $user = $request->user();

        // Un usuario solo puede capturar un cupón una vez (restricción
        // única en la tabla), así que hay como mucho una captura por
        // cupón aquí.
        $captures = DB::table('coupon_captures')
            ->where('user_id', $user->id)
            ->get()
            ->keyBy('coupon_id');

        $capturedIds = $captures->keys()->all();

        $coupons = Coupon::with('category')
            ->whereIn('id', $capturedIds)
            ->orderByDesc('id')
            ->get();

        return response()->json($coupons->map(function ($c) use ($captures, $capturedIds) {
            $capture = $captures[$c->id] ?? null;

            return array_merge($this->formatForUser($c, $capturedIds), [
                'captureCode' => $capture->capture_code ?? null,
                'capturePhotoUrl' => $capture->photo_path ?? null,
                'redeemed' => $capture !== null && $capture->redeemed_at !== null,
                'redeemedAt' => ($capture && $capture->redeemed_at)
                    ? Carbon::parse($capture->redeemed_at)->format('d/m/Y H:i')
                    : null,
            ]);
        }));
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

        $user = $request->user();

        // Todo dentro de una transacción con el cupón bloqueado: si dos
        // personas capturan el último cupo al mismo tiempo, solo una lo
        // logra (antes las dos podían pasar la validación).
        $error = DB::transaction(function () use ($request, $data, $coupon, $user) {
            $locked = Coupon::whereKey($coupon->id)->lockForUpdate()->first();

            if (!$locked || !$locked->active) {
                return response()->json(['message' => 'Este cupón ya no está activo'], 422);
            }

            if ($this->isExpired($locked)) {
                return response()->json(['message' => 'Este cupón ya venció'], 422);
            }

            // Un usuario solo puede capturar un cupón dado una vez
            // (restricción única coupon_id + user_id en la tabla).
            $alreadyCaptured = CouponCapture::where('coupon_id', $locked->id)
                ->where('user_id', $user->id)
                ->exists();

            if ($alreadyCaptured) {
                return response()->json([
                    'message' => 'Ya capturaste este cupón anteriormente',
                ], 422);
            }

            // Cupo GLOBAL compartido entre todos los usuarios.
            if (($locked->captures_count ?? 0) >= ($locked->max_captures ?? 1)) {
                return response()->json([
                    'message' => 'Este cupón ya alcanzó el máximo de capturas disponibles',
                ], 422);
            }

            // La foto se guarda hasta que todas las validaciones pasaron
            // (antes quedaban archivos huérfanos si se rechazaba).
            $path = $request->file('photo')->store('captures', 'public');

            // forceFill: no depende del $fillable del modelo, y el
            // capture_code se guarda en el mismo INSERT.
            $capture = new CouponCapture();
            $capture->forceFill([
                'coupon_id' => $locked->id,
                'user_id' => $user->id,
                'photo_path' => asset('storage/' . $path),
                'capture_code' => $this->generateCaptureCode(),
                'latitude' => $data['latitude'],
                'longitude' => $data['longitude'],
                'captured_at' => now(),
            ])->save();

            $locked->increment('captures_count');

            return null;
        });

        if ($error !== null) {
            return $error;
        }

        return response()->json([
            'message' => 'Cupón capturado correctamente',
            'coupon' => $this->formatForUser(
                $coupon->fresh('category'),
                [$coupon->id]
            ),
        ]);
    }

    // GET /api/admin/coupons -> panel de administrador.
    // Un administrador solo ve los cupones de SUS negocios;
    // el súper administrador los ve todos.
    public function adminIndex(Request $request)
    {
        $query = Coupon::with('category')->orderByDesc('id');

        if ($request->user()->role === 'administrador') {
            $query->where('admin_id', $request->user()->id);
        }

        $coupons = $query->get();

        // Cuántas veces se canjeó cada cupón, en una sola consulta
        // (evita una query por fila).
        $redeemedCounts = DB::table('redemptions')
            ->select('coupon_id', DB::raw('COUNT(*) as cnt'))
            ->whereIn('coupon_id', $coupons->pluck('id'))
            ->groupBy('coupon_id')
            ->pluck('cnt', 'coupon_id');

        return response()->json(
            $coupons->map(fn ($c) => $this->format($c, (int) ($redeemedCounts[$c->id] ?? 0)))
        );
    }

    // POST /api/admin/coupons  (multipart/form-data)
    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:150',
            'business' => 'required|string|max:150',
            'discount' => 'required|string|max:30',
            'coupon_type' => 'nullable|in:producto,porcentaje,dinero',
            'expires_at' => 'required|date',
            'category' => 'required|string',
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'photo' => 'nullable|image|max:4096',
            'token_id' => 'nullable|string|max:20|unique:coupons,token_id',
            'max_captures' => 'nullable|integer|min:1',
        ]);

        $business = $this->resolveBusiness($request, $data['business']);
        if (!$business) {
            return response()->json([
                'message' => 'Ese negocio no existe, está inactivo o no está asignado a tu cuenta',
            ], 422);
        }

        $category = Category::firstOrCreate(['name' => $data['category']]);

        $photoUrl = null;
        if ($request->hasFile('photo')) {
            $path = $request->file('photo')->store('coupons', 'public');
            $photoUrl = asset('storage/' . $path);
        }

        // forceFill: no depende del $fillable del modelo Coupon.
        $coupon = new Coupon();
        $coupon->forceFill([
            'token_id' => $data['token_id'] ?? ('TKN-' . strtoupper(Str::random(6))),
            'name' => $data['name'],
            'business' => $business->name,
            'business_id' => $business->id,
            'admin_id' => $business->admin_id,
            'discount' => $data['discount'],
            'coupon_type' => $this->resolveType($data['coupon_type'] ?? null, $data['discount']),
            'expires_at' => $data['expires_at'],
            'category_id' => $category->id,
            'photo_url' => $photoUrl,
            'latitude' => $data['latitude'],
            'longitude' => $data['longitude'],
            'max_captures' => $data['max_captures'] ?? 1,
            'created_by' => $request->user()->id,
        ])->save();

        return response()->json($this->format($coupon->load('category')), 201);
    }

    // PUT /api/admin/coupons/{id}
    public function update(Request $request, $id)
    {
        $coupon = Coupon::findOrFail($id);
        if ($denied = $this->denyIfNotOwner($request, $coupon)) {
            return $denied;
        }

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:150',
            'business' => 'sometimes|required|string|max:150',
            'discount' => 'sometimes|required|string|max:30',
            'coupon_type' => 'nullable|in:producto,porcentaje,dinero',
            'expires_at' => 'sometimes|required|date',
            'category' => 'sometimes|required|string',
            'latitude' => 'sometimes|required|numeric',
            'longitude' => 'sometimes|required|numeric',
            'photo' => 'nullable|image|max:4096',
            'max_captures' => 'nullable|integer|min:1',
        ]);

        if (isset($data['category'])) {
            $category = Category::firstOrCreate(['name' => $data['category']]);
            $coupon->category_id = $category->id;
        }

        if (isset($data['business'])) {
            $business = $this->resolveBusiness($request, $data['business']);
            if (!$business) {
                return response()->json([
                    'message' => 'Ese negocio no existe, está inactivo o no está asignado a tu cuenta',
                ], 422);
            }
            $coupon->business_id = $business->id;
            $coupon->business = $business->name;
            $coupon->admin_id = $business->admin_id;
        }

        if ($request->hasFile('photo')) {
            $path = $request->file('photo')->store('coupons', 'public');
            $coupon->photo_url = asset('storage/' . $path);
        }

        $coupon->forceFill(
            collect($data)
                ->except(['category', 'business', 'photo'])
                ->reject(fn ($v) => $v === null)
                ->toArray()
        );
        $coupon->save();

        return response()->json($this->format($coupon->load('category')));
    }

    // PATCH /api/admin/coupons/{id}/status
    public function toggleStatus(Request $request, $id)
    {
        $coupon = Coupon::findOrFail($id);
        if ($denied = $this->denyIfNotOwner($request, $coupon)) {
            return $denied;
        }
        $coupon->active = !$coupon->active;
        $coupon->save();

        return response()->json($this->format($coupon->load('category')));
    }

    // DELETE /api/admin/coupons/{id}
    public function destroy(Request $request, $id)
    {
        $coupon = Coupon::findOrFail($id);
        if ($denied = $this->denyIfNotOwner($request, $coupon)) {
            return $denied;
        }
        $coupon->delete();
        return response()->json(['message' => 'Cupón eliminado']);
    }

    // POST /api/coupons/redeem  (uso del ADMINISTRADOR al escanear/cobrar)
    // El código que se escanea es el de la captura del usuario
    // (capture_code): así se sabe EXACTAMENTE cuál captura se está
    // canjeando, y no se puede volver a canjear la misma dos veces.
    // Si el código no corresponde a ninguna captura (por ejemplo, el
    // administrador tecleó el id/token del cupón a mano), se hace un
    // canje "genérico" del cupón, sin ligarlo a un usuario en particular
    // — mismo comportamiento que existía antes de este cambio.
    public function redeem(Request $request)
    {
        $request->validate(['code' => 'required|string']);
        $code = trim($request->code);

        $capture = DB::table('coupon_captures')->where('capture_code', $code)->first();
        if ($capture) {
            return $this->redeemCapture($request, $capture);
        }

        $coupon = Coupon::where('token_id', $code)->first();

        // "C-001", "c-1" o "1" -> id numérico. Solo si el texto es
        // realmente un número (antes MySQL convertía "5abc" en 5).
        if (!$coupon && preg_match('/^(?:[Cc]-)?(\d+)$/', $code, $m)) {
            $coupon = Coupon::find((int) $m[1]);
        }

        if (!$coupon) {
            return response()->json(['message' => 'Código no encontrado'], 404);
        }

        if ($denied = $this->denyIfNotOwner($request, $coupon)) {
            return $denied;
        }

        if ($error = $this->denyIfNotRedeemable($coupon)) {
            return $error;
        }

        // Si el cupón ya tiene capturas de usuarios, el canje debe hacerse
        // con el código de la captura (CAP-...) para que quede registrado
        // en el control de "Mis cupones" del usuario.
        if (DB::table('coupon_captures')->where('coupon_id', $coupon->id)->exists()) {
            return response()->json([
                'message' => 'Escanea el código de canje (CAP-...) que muestra el usuario',
            ], 422);
        }

        $this->recordRedemption($coupon, null, $request->user()?->id);

        return response()->json([
            'message' => 'Cupón canjeado',
            'coupon' => $this->format($coupon),
        ]);
    }

    private function redeemCapture(Request $request, object $capture)
    {
        if ($capture->redeemed_at !== null) {
            return response()->json(['message' => 'Este cupón ya fue canjeado'], 422);
        }

        $coupon = Coupon::find($capture->coupon_id);
        if (!$coupon) {
            return response()->json(['message' => 'Cupón no encontrado'], 404);
        }

        if ($denied = $this->denyIfNotOwner($request, $coupon)) {
            return $denied;
        }

        if ($error = $this->denyIfNotRedeemable($coupon)) {
            return $error;
        }

        $adminId = $request->user()?->id;

        return DB::transaction(function () use ($capture, $coupon, $adminId) {
            // UPDATE condicionado: si dos administradores escanean el
            // mismo código a la vez, solo uno logra marcarlo.
            $updated = DB::table('coupon_captures')
                ->where('id', $capture->id)
                ->whereNull('redeemed_at')
                ->update([
                    'redeemed_at' => now(),
                    'redeemed_by' => $adminId,
                ]);

            if ($updated === 0) {
                return response()->json(['message' => 'Este cupón ya fue canjeado'], 422);
            }

            $this->recordRedemption($coupon, $capture->id, $adminId);

            return response()->json([
                'message' => 'Cupón canjeado',
                'coupon' => $this->format($coupon),
            ]);
        });
    }

    /**
     * Registra el canje y la comisión que gana la plataforma, según el
     * tipo de cupón (producto / porcentaje / dinero) y las tarifas del
     * negocio. $captureId es null en un canje genérico (sin usuario).
     */
    private function recordRedemption(Coupon $coupon, ?int $captureId, ?int $adminId): void
    {
        $type = $coupon->coupon_type ?: 'porcentaje';
        $business = $coupon->business_id ? Business::find($coupon->business_id) : null;

        $commission = 0.0;
        if ($business) {
            $commission = (float) match ($type) {
                'producto' => $business->commission_product,
                'dinero' => $business->commission_money,
                default => $business->commission_percent,
            };
        }

        // DB::table: no depende del $fillable del modelo Redemption.
        DB::table('redemptions')->insert([
            'coupon_id' => $coupon->id,
            'capture_id' => $captureId,
            'business_id' => $coupon->business_id,
            'coupon_type' => $type,
            'commission' => $commission,
            'redeemed_by' => $adminId,
            'redeemed_at' => now(),
        ]);
    }

    /**
     * Código único de canje para una captura de usuario. Distinto para
     * cada persona que capture el mismo cupón, aunque compartan el
     * mismo token_id del cupón.
     */
    private function generateCaptureCode(): string
    {
        do {
            $code = 'CAP-' . strtoupper(Str::random(8));
        } while (DB::table('coupon_captures')->where('capture_code', $code)->exists());

        return $code;
    }

    /**
     * Un administrador solo puede modificar / canjear cupones de SUS
     * negocios (coupons.admin_id = su id). El súper administrador puede
     * todo.
     */
    private function denyIfNotOwner(Request $request, Coupon $coupon)
    {
        $user = $request->user();
        if ($user->role === 'administrador' && (int) $coupon->admin_id !== (int) $user->id) {
            return response()->json([
                'message' => 'Este cupón no pertenece a tus negocios',
            ], 403);
        }
        return null;
    }

    /** Un cupón dado de baja o vencido no se puede canjear. */
    private function denyIfNotRedeemable(Coupon $coupon)
    {
        if (!$coupon->active) {
            return response()->json(['message' => 'Ese cupón está dado de baja'], 422);
        }
        if ($this->isExpired($coupon)) {
            return response()->json(['message' => 'Ese cupón ya venció'], 422);
        }
        return null;
    }

    /**
     * El cupón vale HASTA el final del día de vencimiento (antes se
     * consideraba vencido desde las 00:00 de ese mismo día).
     */
    private function isExpired(Coupon $c): bool
    {
        return $c->expires_at !== null
            && $c->expires_at->copy()->endOfDay()->isPast();
    }

    /**
     * Tipo de cupón. Si no viene explícito, se deduce del texto del
     * descuento: "%" = porcentaje, "$" = dinero, otro = porcentaje.
     */
    private function resolveType(?string $explicit, string $discount): string
    {
        if ($explicit) {
            return $explicit;
        }
        if (str_contains($discount, '$')) {
            return 'dinero';
        }
        return 'porcentaje';
    }

    /**
     * Un administrador solo puede usar negocios ACTIVOS asignados a él.
     * El súper administrador puede usar cualquier negocio activo.
     * Ya NO se crean negocios automáticamente desde un cupón.
     */
    private function resolveBusiness(Request $request, string $name): ?Business
    {
        $query = Business::where('name', $name)->where('active', true);

        if ($request->user()->role === 'administrador') {
            $query->where('admin_id', $request->user()->id);
        }

        return $query->first();
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

    private function format(Coupon $c, int $redeemedCount = 0): array
    {
        $max = $c->max_captures ?? 1;
        $capturesCount = $c->captures_count ?? 0;
        $remaining = max(0, $max - $capturesCount);

        return [
            'id' => 'C-' . str_pad((string) $c->id, 3, '0', STR_PAD_LEFT),
            'numericId' => (string) $c->id,
            'tokenId' => $c->token_id,
            'name' => $c->name,
            'business' => $c->business,
            'discount' => $c->discount,
            'couponType' => $c->coupon_type ?? 'porcentaje',
            'expiresAt' => $c->expires_at?->format('d/m/Y'),
            'expiresAtIso' => $c->expires_at?->format('Y-m-d'),
            'category' => $c->category->name ?? 'Otro',
            'photoUrl' => $c->photo_url,
            'latitude' => $c->latitude,
            'longitude' => $c->longitude,
            'active' => $c->active,
            'isExpired' => $this->isExpired($c),
            'maxCaptures' => $max,
            'capturesCount' => $capturesCount,
            'remainingCaptures' => $remaining,
            'redeemedCount' => $redeemedCount,
        ];
    }

    /**
     * @param array $capturedIds ids de los cupones que ESTE usuario ya
     *                           capturó (se calcula una sola vez por
     *                           petición, no por cupón).
     */
    private function formatForUser(Coupon $c, array $capturedIds): array
    {
        // "¿Ya lo capturé yo?" — determina si el botón sigue
        // disponible PARA ESTE usuario (aunque queden cupos
        // globales, si él ya lo capturó no puede repetir).
        $alreadyCaptured = in_array($c->id, $capturedIds);

        $formatted = $this->format($c);

        return array_merge($formatted, [
            'captureAvailable' => $formatted['remainingCaptures'] > 0
                && !$alreadyCaptured
                && $c->active
                && !$formatted['isExpired'],
            'alreadyCaptured' => $alreadyCaptured,
        ]);
    }
}