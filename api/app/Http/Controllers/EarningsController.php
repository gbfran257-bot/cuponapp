<?php

namespace App\Http\Controllers;

use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class EarningsController extends Controller
{
    // GET /api/super-admin/earnings
    public function summary(Request $request)
    {
        return response()->json([
            'month' => $this->period(now()->startOfMonth()),
            'all' => $this->period(null),
        ]);
    }

    // GET /api/super-admin/redemptions
    // Canjes del mes actual, con su comisión y si ya se pagó.
    public function redemptions()
    {
        $rows = DB::table('redemptions as r')
            ->join('coupons as c', 'c.id', '=', 'r.coupon_id')
            ->leftJoin('businesses as b', 'b.id', '=', 'r.business_id')
            ->leftJoin('users as u', 'u.id', '=', 'b.admin_id')
            ->where('r.redeemed_at', '>=', now()->startOfMonth())
            ->orderByDesc('r.redeemed_at')
            ->select(
                'r.id',
                'c.name as coupon_name',
                DB::raw('COALESCE(b.name, c.business) as business_name'),
                'u.name as admin_name',
                'r.coupon_type',
                'r.commission',
                'r.redeemed_at',
                'r.paid_at'
            )
            ->get()
            ->map(fn ($r) => [
                'id' => (int) $r->id,
                'couponName' => $r->coupon_name,
                'business' => $r->business_name,
                'adminName' => $r->admin_name,
                'couponType' => $r->coupon_type,
                'commission' => (float) $r->commission,
                'date' => Carbon::parse($r->redeemed_at)->format('d/m/Y H:i'),
                'paid' => $r->paid_at !== null,
            ])
            ->values();

        return response()->json($rows);
    }

    // PATCH /api/super-admin/redemptions/{id}/paid
    public function markPaid($id)
    {
        $redemption = DB::table('redemptions')->where('id', $id)->first();

        if (!$redemption) {
            return response()->json(['message' => 'Canje no encontrado'], 404);
        }

        if ($redemption->coupon_type === null) {
            return response()->json([
                'message' => 'Este canje es anterior al sistema de comisiones y no genera ganancia',
            ], 422);
        }

        if ($redemption->paid_at === null) {
            DB::table('redemptions')->where('id', $id)->update(['paid_at' => now()]);
        }

        return response()->json(['message' => 'Canje marcado como pagado']);
    }

    /**
     * Ganancias (comisiones) de los canjes. Si $from es null, cuenta todo.
     * Solo suman los canjes marcados como pagados (paid_at) y los que ya
     * tienen tipo de cupón (los anteriores a la actualización no suman).
     */
    private function period($from): array
    {
        $base = fn () => DB::table('redemptions as r')
            ->whereNotNull('r.coupon_type')
            ->whereNotNull('r.paid_at') // solo comisiones ya pagadas
            ->when($from, fn ($q) => $q->where('r.redeemed_at', '>=', $from));

        $types = $base()
            ->select(
                'r.coupon_type',
                DB::raw('COUNT(*) as cnt'),
                DB::raw('COALESCE(SUM(r.commission), 0) as total')
            )
            ->groupBy('r.coupon_type')
            ->get()
            ->keyBy('coupon_type');

        $byType = [];
        foreach (['producto', 'porcentaje', 'dinero'] as $type) {
            $row = $types->get($type);
            $byType[] = [
                'type' => $type,
                'count' => (int) ($row->cnt ?? 0),
                'total' => (float) ($row->total ?? 0),
            ];
        }

        $byBusiness = $base()
            ->join('businesses as b', 'b.id', '=', 'r.business_id')
            ->leftJoin('users as u', 'u.id', '=', 'b.admin_id')
            ->select(
                'b.id',
                'b.name',
                'u.name as admin_name',
                DB::raw('COUNT(*) as cnt'),
                DB::raw('COALESCE(SUM(r.commission), 0) as total')
            )
            ->groupBy('b.id', 'b.name', 'u.name')
            ->orderByDesc('total')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'name' => $r->name,
                'adminName' => $r->admin_name,
                'count' => (int) $r->cnt,
                'total' => (float) $r->total,
            ])
            ->values();

        return [
            'total' => array_sum(array_column($byType, 'total')),
            'count' => array_sum(array_column($byType, 'count')),
            'byType' => $byType,
            'byBusiness' => $byBusiness,
        ];
    }
}