<?php

namespace App\Http\Controllers;

use App\Models\Business;
use App\Models\Coupon;
use App\Models\Redemption;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class SuperAdminController extends Controller
{
    private function ensureSuperAdmin(Request $request): void
    {
        abort_unless($request->user()->role === 'super_administrador', 403, 'No autorizado');
    }

    // GET /api/super-admin/stats
    public function stats(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $activeBusinessModels = Business::where('active', true)->orderBy('name')->get();

        $activeCoupons = Coupon::where('active', true)
            ->orderByDesc('id')
            ->get(['name', 'business']);

        $redeemedThisMonth = Redemption::with('coupon')
            ->whereMonth('redeemed_at', now()->month)
            ->whereYear('redeemed_at', now()->year)
            ->orderByDesc('redeemed_at')
            ->get()
            ->map(fn ($r) => [
                'couponName' => $r->coupon->name ?? 'Cupón eliminado',
                'business' => $r->coupon->business ?? '',
                'date' => $r->redeemed_at->translatedFormat('d M'),
            ]);

        $adminsCount = User::where('role', 'administrador')->count();

        return response()->json([
            'stats' => [
                'Negocios activos' => (string) $activeBusinessModels->count(),
                'Administradores' => (string) $adminsCount,
                'Cupones activos' => (string) $activeCoupons->count(),
                'Cupones canjeados (mes)' => (string) $redeemedThisMonth->count(),
            ],
            'activeBusinesses' => $activeBusinessModels->pluck('name')->values(),
            'activeCoupons' => $activeCoupons,
            'redeemedThisMonth' => $redeemedThisMonth,
        ]);
    }

    // ── Negocios ─────────────────────────────────────────────

    public function businesses(Request $request)
    {
        $this->ensureSuperAdmin($request);

        return response()->json(
            Business::orderBy('name')->get()->map(fn ($b) => $this->formatBusiness($b))
        );
    }

    public function storeBusiness(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $data = $request->validate([
            'name' => 'required|string|max:150|unique:businesses,name',
        ]);

        $business = Business::create([
            'name' => $data['name'],
            'active' => true,
        ]);

        return response()->json($this->formatBusiness($business), 201);
    }

    public function updateBusiness(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        $business = Business::findOrFail($id);

        $data = $request->validate([
            'name' => 'required|string|max:150|unique:businesses,name,' . $business->id,
        ]);

        $business->name = $data['name'];
        $business->save();

        // Mantiene sincronizado el texto guardado en cada cupón de este negocio.
        Coupon::where('business_id', $business->id)->update(['business' => $business->name]);

        return response()->json($this->formatBusiness($business));
    }

    public function toggleBusinessStatus(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        $business = Business::findOrFail($id);
        $business->active = !$business->active;
        $business->save();

        return response()->json($this->formatBusiness($business));
    }

    public function destroyBusiness(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        Business::findOrFail($id)->delete();

        return response()->json(['message' => 'Negocio eliminado']);
    }

    private function formatBusiness(Business $b): array
    {
        return [
            'id' => (string) $b->id,
            'name' => $b->name,
            'active' => (bool) $b->active,
        ];
    }

    // ── Administradores ──────────────────────────────────────

    public function admins(Request $request)
    {
        $this->ensureSuperAdmin($request);

        return response()->json(
            User::where('role', 'administrador')->orderBy('name')->get()
                ->map(fn ($u) => $this->formatUser($u))
        );
    }

    public function storeAdmin(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $data = $request->validate([
            'name' => 'required|string|max:150',
            'email' => 'required|email|max:150|unique:users,email',
            'password' => 'required|string|min:6',
        ]);

        $admin = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => 'administrador',
        ]);

        return response()->json($this->formatUser($admin), 201);
    }

    public function updateAdmin(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        $admin = User::where('role', 'administrador')->findOrFail($id);

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:150',
            'email' => 'sometimes|required|email|max:150|unique:users,email,' . $admin->id,
            'password' => 'nullable|string|min:6',
        ]);

        if (!empty($data['password'])) {
            $admin->password = Hash::make($data['password']);
        }
        $admin->fill(collect($data)->except('password')->toArray());
        $admin->save();

        return response()->json($this->formatUser($admin));
    }

    public function toggleAdminStatus(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        $admin = User::where('role', 'administrador')->findOrFail($id);
        $admin->active = !$admin->active;
        $admin->save();

        return response()->json($this->formatUser($admin));
    }

    public function destroyAdmin(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        User::where('role', 'administrador')->findOrFail($id)->delete();

        return response()->json(['message' => 'Administrador eliminado']);
    }

    // ── Usuarios ─────────────────────────────────────────────

    public function users(Request $request)
    {
        $this->ensureSuperAdmin($request);

        return response()->json(
            User::where('role', 'usuario')->orderBy('name')->get()
                ->map(fn ($u) => $this->formatUser($u))
        );
    }

    public function storeUser(Request $request)
    {
        $this->ensureSuperAdmin($request);

        $data = $request->validate([
            'name' => 'required|string|max:150',
            'email' => 'required|email|max:150|unique:users,email',
            'password' => 'required|string|min:6',
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => 'usuario',
        ]);

        return response()->json($this->formatUser($user), 201);
    }

    public function updateUser(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        $user = User::where('role', 'usuario')->findOrFail($id);

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:150',
            'email' => 'sometimes|required|email|max:150|unique:users,email,' . $user->id,
            'password' => 'nullable|string|min:6',
        ]);

        if (!empty($data['password'])) {
            $user->password = Hash::make($data['password']);
        }
        $user->fill(collect($data)->except('password')->toArray());
        $user->save();

        return response()->json($this->formatUser($user));
    }

    public function toggleUserStatus(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        $user = User::where('role', 'usuario')->findOrFail($id);
        $user->active = !$user->active;
        $user->save();

        return response()->json($this->formatUser($user));
    }

    public function destroyUser(Request $request, $id)
    {
        $this->ensureSuperAdmin($request);

        User::where('role', 'usuario')->findOrFail($id)->delete();

        return response()->json(['message' => 'Usuario eliminado']);
    }

    private function formatUser(User $u): array
    {
        return [
            'id' => (string) $u->id,
            'name' => $u->name,
            'email' => $u->email,
            'active' => (bool) $u->active,
        ];
    }
}