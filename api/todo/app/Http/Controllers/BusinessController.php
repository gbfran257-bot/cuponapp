<?php

namespace App\Http\Controllers;

use App\Models\Business;
use App\Models\Coupon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class BusinessController extends Controller
{
    // GET /api/super-admin/businesses
    public function index()
    {
        return response()->json(
            Business::with('admin')->orderBy('name')->get()
                ->map(fn ($b) => $this->format($b))
        );
    }

    // POST /api/super-admin/businesses
    public function store(Request $request)
    {
        $data = $request->validate($this->rules());
        $data['active'] = true;

        $business = Business::create($data);

        return response()->json($this->format($business->load('admin')), 201);
    }

    // PUT /api/super-admin/businesses/{id}
    public function update(Request $request, $id)
    {
        $business = Business::findOrFail($id);
        $business->update($request->validate($this->rules($business->id)));

        // Si cambió el administrador asignado, sus cupones pasan al nuevo.
        Coupon::where('business_id', $business->id)
            ->update(['admin_id' => $business->admin_id]);

        return response()->json($this->format($business->load('admin')));
    }

    // PATCH /api/super-admin/businesses/{id}/status
    public function toggleStatus($id)
    {
        $business = Business::findOrFail($id);
        $business->active = !$business->active;
        $business->save();

        return response()->json($this->format($business->load('admin')));
    }

    // DELETE /api/super-admin/businesses/{id}
    public function destroy($id)
    {
        Business::findOrFail($id)->delete();
        return response()->json(['message' => 'Negocio eliminado']);
    }

    // GET /api/admin/my-businesses
    // Negocios ACTIVOS que el administrador puede usar al crear cupones.
    // (El súper administrador ve todos los activos.)
    public function mine(Request $request)
    {
        $query = Business::where('active', true)->orderBy('name');

        if ($request->user()->role === 'administrador') {
            $query->where('admin_id', $request->user()->id);
        }

        return response()->json(
            $query->get()->map(fn ($b) => [
                'id' => (string) $b->id,
                'name' => $b->name,
            ])->values()
        );
    }

    private function rules(?int $ignoreId = null): array
    {
        return [
            'name' => ['required', 'string', 'min:2', 'max:150',
                       Rule::unique('businesses', 'name')->ignore($ignoreId)],
            'admin_id' => ['required', Rule::exists('users', 'id')
                            ->where('role', 'administrador')],
            'address' => 'nullable|string|max:255',
            'phone' => 'nullable|string|max:20',
            'commission_product' => 'required|numeric|min:0',
            'commission_percent' => 'required|numeric|min:0',
            'commission_money' => 'required|numeric|min:0',
            'contact_name' => 'nullable|string|max:150',
            'contact_email' => 'nullable|email|max:150',
            'rfc' => 'nullable|string|max:13',
            'description' => 'nullable|string',
        ];
    }

    private function format(Business $b): array
    {
        return [
            'id' => (string) $b->id,
            'name' => $b->name,
            'active' => (bool) $b->active,
            'adminId' => $b->admin_id ? (string) $b->admin_id : null,
            'adminName' => $b->admin?->name,
            'address' => $b->address,
            'phone' => $b->phone,
            'commissionProduct' => (float) $b->commission_product,
            'commissionPercent' => (float) $b->commission_percent,
            'commissionMoney' => (float) $b->commission_money,
            'contactName' => $b->contact_name,
            'contactEmail' => $b->contact_email,
            'rfc' => $b->rfc,
            'description' => $b->description,
        ];
    }
}